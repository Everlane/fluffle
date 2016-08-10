require 'concurrent'
require 'oj'
require 'securerandom'
require 'uuidtools'

require 'fluffle/connectable'

module Fluffle
  class Client
    include Connectable

    attr_accessor :default_timeout
    attr_accessor :logger

    def initialize(url:)
      @default_timeout = 5
      @logger          = Fluffle.logger

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
        self.handle_reply delivery_info: delivery_info,
                          properties: properties,
                          payload: payload
      end
    end

    # Fetch and set the `IVar` with a response from the server. This method is
    # called from the reply queue's background thread; the main thread will
    # normally be waiting for the `IVar` to be set.
    def handle_reply(delivery_info:, properties:, payload:)
      payload = Oj.load payload
      id      = payload['id']

      ivar = @pending_responses.delete id

      if ivar
        ivar.set payload
      else
        self.logger.error "Missing pending response IVar: id=#{id || 'null'}"
      end
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

      response = publish_and_wait payload, queue: queue,
                                           timeout: timeout

      if response['result']
        response['result']
      else
        error = response['error'] || {}

        raise Errors::CustomError.new code: error['code'] || 0,
                                      message: error['message'] || "Missing both `result' and `error' on Response object",
                                      data: error['data']
      end
    end

    # Publish a payload to the server and wait (block) for the response
    #
    # It creates an `IVar` future for the response, stores that in
    # `@pending_responses`, and then publishes the payload to the server.
    # After publishing it waits for the `IVar` to be set with the response.
    # It also clears that `IVar` if it times out to avoid leaking.
    #
    # Returns a Hash from the JSON response from the server
    # Raises TimeoutError if server failed to respond in time
    def publish_and_wait(payload, queue:, timeout:)
      id = payload['id']

      ivar = Concurrent::IVar.new
      @pending_responses[id] = ivar

      self.publish payload, queue: queue

      response = ivar.value timeout

      if ivar.incomplete?
        method = payload['method']
        arity  = payload['params']&.length || 0
        raise Errors::TimeoutError.new("Timed out waiting for response to `#{method}/#{arity}'")
      end

      return response
    ensure
      # Don't leak the `IVar` if it timed out
      @pending_responses.delete id
    end

    def publish(payload, queue:)
      opts = {
        routing_key: Fluffle.request_queue_name(queue),
        correlation_id: payload['id'],
        reply_to: @reply_queue.name
      }

      @exchange.publish Oj.dump(payload), opts
    end

    protected

    def random_bytes_as_hex(bytes)
      # Adapted from `SecureRandom.hex`
      @prng.bytes(bytes).unpack('H*')[0]
    end
  end
end
