require 'concurrent'
require 'oj'

module Fluffle
  class Server
    include Connectable

    attr_reader :confirms, :connection, :handlers, :handler_pool, :mandatory
    attr_accessor :publish_timeout, :shutdown_timeout

    # url:         - Optional URL to pass to `Bunny.new` to immediately connect
    # concurrency: - Number of threads to handle messages on (default: 1)
    # confirms:    - Whether or not to use RabbitMQ confirms
    def initialize(url: nil, connection: nil, concurrency: 1, confirms: false, mandatory: false)
      url_or_connection = url || connection
      self.connect(url_or_connection) if url_or_connection

      @confirms         = confirms
      @mandatory        = mandatory
      @publish_timeout  = 5
      @shutdown_timeout = 15

      @handlers     = {}
      @handler_pool = Concurrent::FixedThreadPool.new concurrency
      @consumers    = []

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

      # Ensure we only receive 1 message at a time for each consumer
      @channel.prefetch 1

      if confirms
        @confirmer = Fluffle::Confirmer.new channel: @channel
        @confirmer.confirm_select
      end

      if mandatory
        handle_returns
      end

      raise 'No handlers defined' if @handlers.empty?

      @handlers.each do |name, handler|
        qualified_name = Fluffle.request_queue_name name
        queue          = @channel.queue qualified_name

        consumer = queue.subscribe(manual_ack: true) do |delivery_info, properties, payload|
          @handler_pool.post do
            begin
              handle_request handler: handler,
                             properties: properties,
                             payload: payload
            rescue => err
              # Ensure we don't loose any errors on the handler pool's thread
              Fluffle.logger.error "[Fluffle::Server] #{err.class}: #{err.message}\n#{err.backtrace.join("\n")}"
            ensure
              @channel.ack delivery_info.delivery_tag
            end
          end
        end

        @consumers << consumer
      end

      self.wait_for_signal
    end

    def handle_returns
      @exchange.on_return do |return_info, _properties, _payload|
        message = Kernel.sprintf "Received return from exchange for routing key `%s' (%d %s)", return_info.routing_key, return_info.reply_code, return_info.reply_text
        Fluffle.logger.error "[Fluffle::Server] #{message}"
      end
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

        # First stop the consumers from receiving messages
        @consumers.each &:cancel

        # Then wait for worker pools to finish processing their active jobs
        @handler_pool.shutdown
        unless @handler_pool.wait_for_termination(@shutdown_timeout)
          # `wait_for_termination` returns false if it didn't shut down in time,
          # so we need to kill it
          @handler_pool.kill
        end

        # Finally close the connection
        @channel.close

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

      stack = Fluffle::MiddlewareStack.new

      if confirms
        stack.push ->(publish) {
          @confirmer.with_confirmation timeout: publish_timeout, &publish
        }
      end

      stack.call do
        @exchange.publish Oj.dump(response), routing_key: reply_to,
                                             correlation_id: response['id']
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
  end
end
