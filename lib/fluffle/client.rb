require 'concurrent'
require 'oj'
require 'securerandom'
require 'uuidtools'

require 'fluffle/connectable'

module Fluffle
  class Client
    include Connectable

    def initialize(url:)
      self.connect url

      @uuid        = UUIDTools::UUID.timestamp_create.to_s
      @channel     = @connection.create_channel
      @exchange    = @channel.default_exchange
      @reply_queue = @channel.queue Fluffle.response_queue_name(@uuid), exclusive: true

      @pending_responses = Concurrent::Map.new

      self.subscribe
    end

    def subscribe
      @reply_queue.subscribe do |delivery_info, properties, payload|
        self.handle_resposne delivery_info: delivery_info,
                             properties: properties,
                             payload: payload
      end
    end

    def handle_resposne(delivery_info:, properties:, payload:)
      payload  = Oj.load payload

      ivar = @pending_responses.delete payload['id']
      ivar.set payload
    end

    def call(method, params = [], queue: 'default')
      id = SecureRandom.hex 8

      payload = {
        'jsonrpc' => '2.0',
        'id'      => id,
        'method'  => method,
        'params'  => params
      }

      @exchange.publish Oj.dump(payload), routing_key: Fluffle.request_queue_name(queue),
                                          correlation_id: id,
                                          reply_to: @reply_queue.name

      ivar = Concurrent::IVar.new
      @pending_responses[id] = ivar

      response = ivar.value

      if response['result']
        response['result']
      else
        raise # TODO: Raise known error subclass to be caught by client code
      end
    end
  end
end
