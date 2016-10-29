require 'concurrent'
require 'oj'

module Fluffle
  class Server
    include Connectable

    attr_reader :confirms, :connection, :handlers, :handler_pool
    attr_accessor :publish_timeout

    # url:         - Optional URL to pass to `Bunny.new` to immediately connect
    # concurrency: - Number of threads to handle messages on (default: 1)
    # confirms:    - Whether or not to use RabbitMQ confirms
    def initialize(url: nil, connection: nil, concurrency: 1, confirms: false)
      url_or_connection = url || connection
      self.connect(url_or_connection) if url_or_connection

      @confirms        = confirms
      @publish_timeout = 5

      @handlers     = {}
      @handler_pool = Concurrent::FixedThreadPool.new concurrency

      self.class.default_server ||= self
    end

    class << self
      attr_accessor :default_server
    end

    def drain(queue: 'default', handler: nil, &block)
      if handler && block
        raise ArgumentError, 'Cannot provide both handler: and block'
      end

      handler = Fluffle::Handlers::Dispatcher.new(&block) if block

      raise ArgumentError, 'Handler cannot be nil' if handler.nil?

      @handlers[queue.to_s] = handler
    end

    def start
      @handlers.freeze

      @channel  = @connection.create_channel
      @exchange = @channel.default_exchange

      if confirms
        @pending_confirms = Concurrent::Map.new
        confirm_select
      end

      raise 'No handlers defined' if @handlers.empty?

      @handlers.each do |name, handler|
        qualified_name = Fluffle.request_queue_name name
        queue          = @channel.queue qualified_name

        queue.subscribe(manual_ack: true) do |delivery_info, properties, payload|
          @handler_pool.post do
            begin
              @channel.ack delivery_info.delivery_tag

              handle_request handler: handler,
                             properties: properties,
                             payload: payload
            rescue => err
              # Ensure we don't loose any errors on the handler pool's thread
              Fluffle.logger.error "[Fluffle::Server] #{err.class}: #{err.message}\n#{err.backtrace.join("\n")}"
            end
          end
        end
      end

      self.wait_for_signal
    end

    def confirm_select
      handle_confirm = ->(tag, _multiple, nack) do
        ivar = @pending_confirms.delete tag

        if ivar
          ivar.set nack
        else
          self.logger.error "Missing confirm IVar: tag=#{tag}"
        end
      end

      # Put the channel into confirmation
      @channel.confirm_select handle_confirm
    end

    # NOTE: Keeping this in its own method so its functionality can be more
    #   easily overwritten by `Fluffle::Testing`.
    def wait_for_signal
      signal_read, signal_write = IO.pipe

      %w[INT TERM].each do |signal|
        Signal.trap(signal) do
          signal_write.puts signal
        end
      end

      # Adapted from Sidekiq:
      #   https://github.com/mperham/sidekiq/blob/e634177/lib/sidekiq/cli.rb#L94-L97
      while io = IO.select([signal_read])
        readables = io.first
        signal    = readables.first.gets.strip

        Fluffle.logger.info "Received #{signal}; shutting down..."
        @channel.work_pool.shutdown

        return
      end
    end

    def handle_request(handler:, properties:, payload:)
      reply_to = properties[:reply_to]

      id       = nil
      response = nil

      begin
        request = self.decode payload
        id      = request['id']

        response = self.call_handler handler: handler, request: request
      rescue => err
        response = {
          'jsonrpc' => '2.0',
          'id'      => id,
          'error'   => self.build_error_response(err)
        }
      end

      publish = ->{
        @exchange.publish Oj.dump(response), routing_key: reply_to,
                                             correlation_id: response['id']
      }

      if confirms
        with_confirmation timeout: publish_timeout, &publish
      else
        publish.()
      end
    end

    # handler - Instance of a `Handler` that may receive `#call`
    # request - `Hash` representing a decoded Request
    def call_handler(handler:, request:)
      t0 = Time.now

      begin
        id = request['id']

        self.validate_request request

        result = handler.call id: id,
                              method: request['method'],
                              params: request['params'],
                              meta: {}
      rescue => err
        log_error(err) if Fluffle.logger.error?

        error = self.build_error_response err
      end

      response = {
        'jsonrpc' => '2.0',
        'id'      => id,
        'meta'    => {
          'handler_duration' => (Time.now - t0)
        }
      }

      if error
        response['error'] = error
      else
        response['result'] = result
      end

      response
    end

    # Deserialize a JSON payload and extract its 3 members: id, method, params
    #
    # payload - `String` of the payload from the queue
    #
    # Returns a `Hash` from parsing the JSON payload (keys should be `String`)
    def decode(payload)
      Oj.load payload
    end

    # Raises if elements of the request payload do not comply with the spec
    #
    # payload - Decoded `Hash` of the payload (`String` keys)
    def validate_request(request)
      raise Errors::InvalidRequestError.new("Improperly formatted Request (expected `Hash', got `#{request.class}')") unless request && request.is_a?(Hash)
      raise Errors::InvalidRequestError.new("Missing `method' Request object member") unless request['method']
    end

    protected

    # Logs a nicely-formmated error to `Fluffle.logger` with the class,
    # message, and backtrace (if available)
    def log_error(err)
      backtrace = Array(err.backtrace).flatten.compact

      backtrace =
        if backtrace.empty?
          ''
        else
          prefix = "\n  "
          prefix + backtrace.join(prefix)
        end

      message = "#{err.class}: #{err.message}#{backtrace}"
      Fluffle.logger.error message
    end

    # Convert a Ruby error into a hash complying with the JSON-RPC spec
    # for `Error` response objects
    def build_error_response(err)
      if err.is_a? Errors::BaseError
        err.to_response

      elsif err.is_a? NoMethodError
        { 'code' => -32601, 'message' => 'Method not found' }

      else
        response = {
          'code' => 0,
          'message' => "#{err.class}: #{err.message}"
        }

        response['data'] = err.data if err.respond_to? :data

        response
      end
    end

    # Wraps a block (which should publish a message) with a blocking check
    #   that the client received a confirmation from the RabbitMQ server
    #   that the message that was received and routed successfully
    def with_confirmation(timeout:)
      tag = @channel.next_publish_seq_no
      confirm_ivar = Concurrent::IVar.new
      @pending_confirms[tag] = confirm_ivar

      yield

      nack = confirm_ivar.value timeout
      if confirm_ivar.incomplete?
        raise Errors::TimeoutError.new('Timed out waiting for confirm')
      elsif nack
        raise Errors::NackError.new('Received nack from confirmation')
      end
    end
  end
end
