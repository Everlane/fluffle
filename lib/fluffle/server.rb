module Fluffle
  class Server
    include Connectable

    attr_reader :connection, :handlers

    def initialize(url: nil)
      self.connect(url) if url

      @handlers = {}
      @queues   = {}

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

      @handlers.each do |name, handler|
        qualified_name = Fluffle.request_queue_name name
        queue          = @channel.queue qualified_name

        queue.subscribe do |delivery_info, properties, payload|
          self.handle_request queue_name: name,
                              handler: handler,
                              delivery_info: delivery_info,
                              properties: properties,
                              payload: payload
        end
      end

      # Ensure the work pool is running and ready to handle requests
      @channel.work_pool.start

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

    def handle_request(queue_name:, handler:, delivery_info:, properties:, payload:)
      id       = nil
      reply_to = properties[:reply_to]

      begin
        id, method, params = self.decode payload

        validate_request method: method

        result = handler.call id: id,
                              method: method,
                              params: params,
                              meta: {
                                reply_to: reply_to
                              }
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

      @exchange.publish Oj.dump(response), routing_key: reply_to,
                                           correlation_id: id
    end

    protected

    def decode(payload)
      payload = Oj.load payload

      id     = payload['id']
      method = payload['method']
      params = payload['params']

      [id, method, params]
    end

    # Raises if elements of the request do not comply with the spec
    def validate_request(request)
      raise Errors::InvalidRequestError.new("Missing `method' Request object member") unless request[:method]
    end

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
