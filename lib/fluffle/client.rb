require 'concurrent'
require 'oj'
require 'securerandom'
require 'uuidtools'

require 'fluffle/connectable'

module Fluffle
  class Client
    include Connectable

    attr_reader :confirms
    attr_reader :mandatory
    attr_accessor :default_timeout
    attr_accessor :logger

    def initialize(url: nil, connection: nil, confirms: false, mandatory: false)
      self.connect(url || connection)

      @confirms        = confirms
      @mandatory       = mandatory
      @default_timeout = 5
      @logger          = Fluffle.logger

      @uuid        = UUIDTools::UUID.timestamp_create.to_s
      @channel     = @connection.create_channel
      @exchange    = @channel.default_exchange
      @reply_queue = @channel.queue Fluffle.response_queue_name(@uuid), exclusive: true

      # Used for generating unique message IDs
      @prng = Random.new

      if confirms
        @confirmer = Fluffle::Confirmer.new channel: @channel
        @confirmer.confirm_select
      end

      if mandatory
        handle_returns
      end

      @pending_responses = Concurrent::Map.new
      subscribe
    end

    def subscribe
      @reply_queue.subscribe do |delivery_info, properties, payload|
        begin
          self.handle_reply delivery_info: delivery_info,
                            properties: properties,
                            payload: payload
        rescue => err
          # Bunny will let uncaptured errors silently wreck the reply thread,
          # so we must be extra-careful about capturing them
          Fluffle.logger.error "[Fluffle::Client] #{err.class}: #{err.message}\n#{err.backtrace.join("\n")}"
        end
      end
    end

    def handle_returns
      @exchange.on_return do |return_info, properties, _payload|
        id   = properties[:correlation_id]
        ivar = @pending_responses.delete id

        if ivar
          message = Kernel.sprintf "Received return from exchange for routing key `%s' (%d %s)", return_info.routing_key, return_info.reply_code, return_info.reply_text

          error = Fluffle::Errors::ReturnError.new message
          ivar.set error
        end
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

    def call(method, params = [], queue: 'default', raw_response: false, **opts)
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

      return response if raw_response

      if response.key? 'result'
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
    # Returns a `Hash` from the JSON response from the server
    # Raises `Fluffle::Errors::TimeoutError` if the server failed to respond
    #   within the given time in `timeout:`
    def publish_and_wait(payload, queue:, timeout:)
      id = payload['id']

      response_ivar = Concurrent::IVar.new
      @pending_responses[id] = response_ivar

      stack = Fluffle::MiddlewareStack.new

      if confirms
        stack.push ->(publish) do
          @confirmer.with_confirmation timeout: timeout, &publish
        end
      end

      stack.call do
        publish payload, queue: queue
      end

      response = response_ivar.value timeout

      if response_ivar.incomplete?
        raise Errors::TimeoutError.new("Timed out waiting for response to `#{describe_payload(payload)}'")
      elsif response.is_a? StandardError
        # Exchange returns will preempt the response and set it to an error
        # that we can raise
        raise response
      end

      return response
    ensure
      # Don't leak the `IVar` if it timed out
      @pending_responses.delete id
    end

    # Returns a nice formatted description of a payload with its method name
    #   and arity
    def describe_payload(payload)
      method = payload['method']
      arity  = (payload['params'] && payload['params'].length) || 0

      "#{method}/#{arity}"
    end

    def publish(payload, queue:)
      opts = {
        routing_key: Fluffle.request_queue_name(queue),
        correlation_id: payload['id'],
        reply_to: @reply_queue.name,
        mandatory: @mandatory,
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
