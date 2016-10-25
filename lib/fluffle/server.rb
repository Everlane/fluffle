module Fluffle
  class Server
    include Connectable

    attr_reader :connection, :handlers, :handler_pool

    # url:         - Optional URL to pass to `Bunny.new` to immediately connect
    # concurrency: - Number of threads to handle messages on (default: 1)
    def initialize(url: nil, connection: nil, concurrency: 1)
      url_or_connection = url || connection
      self.connect(url_or_connection) if url_or_connection

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

      @handlers[queue.to_s] = handler
    end

    def start
      @channel  = @connection.create_channel
      @exchange = @channel.default_exchange

      raise 'No handlers defined' if @handlers.empty?

      @handlers.each do |name, handler|
        qualified_name = Fluffle.request_queue_name name
        queue          = @channel.queue qualified_name

        queue.subscribe do |_delivery_info, properties, payload|
          @handler_pool.post do
            self.handle_request handler: handler,
                                properties: properties,
                                payload: payload
          end
        end
      end

      self.wait_for_signal
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

      @exchange.publish Oj.dump(response), routing_key: reply_to,
                                           correlation_id: response['id']
    end

    # handler - Instance of a `Handler` that may receive `#call`
    # request - `Hash` representing a decoded Request
    def call_handler(handler:, request:)
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

      response = { 'jsonrpc' => '2.0', 'id' => id }

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
