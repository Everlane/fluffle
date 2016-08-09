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

    def drain(queue_name = 'default', handler: nil, &block)
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
      reply_to = properties[:reply_to]
      payload  = Oj.load payload

      id     = payload['id']
      method = payload['method']
      params = payload['params']

      # TODO: Error handling!
      result = handler.call id: id,
                            method: method,
                            params: params,
                            meta: {
                              reply_to: reply_to
                            }

      payload = { 'jsonrpc' => '2.0', 'id' => id }

      payload['result'] = result

      @exchange.publish Oj.dump(payload), routing_key: reply_to,
                                          correlation_id: id
    end
  end
end
