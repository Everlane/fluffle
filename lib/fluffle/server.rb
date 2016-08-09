module Fluffle
  class Server
    class << self
      attr_accessor :default_server
    end

    attr_reader :connection, :handlers

    def initialize(url: nil)
      self.connect(url) if url

      @handlers = {}
      @queues   = {}

      self.class.default_server ||= self
    end

    def connect(*args)
      self.stop if self.connected?

      @connection = Bunny.new *args
      @connection.start
    end

    def connected?
      @connection&.connected?
    end

    def drain(queue: 'default', handler: nil, &block)
      if handler && block
        raise ArgumentError, 'Cannot provide both handler: and block'
      end

      handler = Fluffle::Handlers::Dispatcher.new(&block) if block

      @handlers[queue_name.to_s] = handler
    end

    def start
      @channel  = @connection.create_channel
      @exchange = @channel.default_exchange

      @handlers.each do |name, handler|
        qualified_name = Fluffle.response_queue_name name
        queue          = @channel.queue qualified_name

        queue.subscribe do |delivery_info, properties, payload|
          self.handle_request queue_name: name,
                              handler: handler,
                              delivery_info: delivery_info,
                              properties: properties,
                              payload: payload
        end
      end

      @channel.work_pool.join
    end

    def handle_request(queue_name:, handler:, delivery_info:, properties:, payload:)
      id       = nil
      reply_to = properties[:reply_to]

      begin
        id, method, params = self.decode_and_verify payload

        result = handler.call id: id,
                              method: method,
                              params: params,
                              meta: {
                                reply_to: reply_to
                              }
      rescue => err
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

    def decode_and_verify(payload)
      payload = Oj.load payload

      id     = payload['id']
      method = payload['method']
      params = payload['params']

      [id, method, params]
    end

    # Convert a Ruby error into a hash complying with the JSON-RPC spec
    # for `Error` response objects
    def build_error_response(err)
      case err
      when NoMethodError
        { 'code' => -32601, 'message' => 'Method not found' }
      else
        response = {
          'code' => 0,
          'message' => err.message
        }

        response['data'] = err.data if err.respond_to? :data

        response
      end
    end
  end
end
