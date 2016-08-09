require 'concurrent'
require 'oj'
require 'securerandom'
require 'uuidtools'

require 'fluffle/connectable'

module Fluffle
  class Client
    include Connectable

    attr_accessor :default_timeout

    def initialize(url:)
      @default_timeout = 5

      self.connect url

      @uuid        = UUIDTools::UUID.timestamp_create.to_s
      @channel     = @connection.create_channel
      @exchange    = @channel.default_exchange
      @reply_queue = @channel.queue Fluffle.response_queue_name(@uuid), exclusive: true

      # Used for generating unique message IDs
      @prng = Random.new

      @pending_responses = Concurrent::Map.new

      self.subscribe
    end

    def subscribe
      @reply_queue.subscribe do |delivery_info, properties, payload|
        self.handle_response delivery_info: delivery_info,
                             properties: properties,
                             payload: payload
      end
    end

    def handle_response(delivery_info:, properties:, payload:)
      payload = Oj.load payload

      ivar = @pending_responses.delete payload['id']
      ivar.set payload
    end

    def call(method, params = [], queue: 'default', **opts)
      # Using `.fetch` here so that we can pass `nil` as the timeout and have
      # it be respected
      timeout = opts.fetch :timeout, self.default_timeout

      id = random_bytes_as_hex 8

      payload = {
        'jsonrpc' => '2.0',
        'id'      => id,
        'method'  => method,
        'params'  => params
      }

      ivar = Concurrent::IVar.new
      @pending_responses[id] = ivar

      @exchange.publish Oj.dump(payload), routing_key: Fluffle.request_queue_name(queue),
                                          correlation_id: id,
                                          reply_to: @reply_queue.name

      response = ivar.value timeout

      if ivar.incomplete?
        raise Errors::TimeoutError.new("Timed out waiting for response to `#{method}/#{params.length}'")
      end

      if response['result']
        response['result']
      else
        error = response['error'] || {}

        raise Errors::CustomError.new code: error['code'] || 0,
                                      message: error['message'] || "Missing both `result' and `error' on Response object",
                                      data: error['data']
      end
    end

    protected

    def random_bytes_as_hex(bytes)
      # Adapted from `SecureRandom.hex`
      @prng.bytes(bytes).unpack('H*')[0]
    end
  end
end
