require 'concurrent'

module Fluffle
  module Testing
    class << self
      def setup!(use_fake_thread_pool: true)
        # Inject our own custom `Connectable` implementation
        [Fluffle::Client, Fluffle::Server].each do |mod|
          mod.include Connectable
        end

        Fluffle::Server.class_eval do
          # Overwriting this so that we don't actually block waiting for signal
          def wait_for_signal
            # pass
          end
        end

        if use_fake_thread_pool
          Fluffle::Server.class_eval do
            # Wrap the `initialize` implementation to switch out the handler pool
            # to a local unthreaded one
            alias_method :original_initialize, :initialize

            def initialize(*args)
              original_initialize *args

              @handler_pool = ThreadPool.new
            end
          end
        end
      end
    end # class << self

    # Patch in a new `#connect` method that injects the loopback
    module Connectable
      def self.included(klass)
        klass.class_eval do
          alias_method :original_connect, :connect

          def connect(*args)
            @connection = Loopback.instance.connection
          end
        end
      end
    end

    # Fake thread pool that executes `#post`'ed blocks immediately in the
    # current thread
    class ThreadPool
      def post(&block)
        block.call
      end
    end

    DeliveryInfo = Struct.new(:delivery_tag)

    # Fake RabbitMQ server presented through a subset of the `Bunny`
    # library's interface
    class Loopback
      # Singleton server instance that lives in the process
      def self.instance
        @instance ||= self.new
      end

      def initialize
        @queues = Concurrent::Map.new
      end

      def connection
        Connection.new self
      end

      def add_queue_subscriber(queue_name, block)
        subscribers = (@queues[queue_name] ||= Concurrent::Array.new)

        subscribers << block
      end

      def publish(payload, opts)
        queue_name = opts[:routing_key]
        raise "Missing `:routing_key' in `#publish' opts" unless queue_name

        delivery_info = DeliveryInfo.new Random.rand(1000000)

        properties = {
          reply_to: opts[:reply_to],
          correlation_id: opts[:correlation_id]
        }

        subscribers = @queues[queue_name]

        if subscribers.nil? || subscribers.empty?
          $stderr.puts "No subscribers active for queue '#{queue_name}'"
          return nil
        end

        subscribers.each do |subscriber|
          subscriber.call(delivery_info, properties, payload)
        end
      end

      class Connection
        def initialize(server)
          @server = server
        end

        def create_channel
          Channel.new(@server)
        end
      end

      class Channel
        def initialize(server)
          @server = server

          @confirm_select      = nil
          @next_publish_seq_no = 0
        end

        def default_exchange
          @default_exchange ||= Exchange.new(@server, self)
        end

        def work_pool
          @work_pool ||= WorkPool.new
        end

        def confirm_select(block = nil)
          @confirm_select      = block
          @next_publish_seq_no = 1
        end

        def next_publish_seq_no
          @next_publish_seq_no
        end

        def queue(name, **opts)
          opts = opts.merge server: @server

          Queue.new name, opts
        end

        def publish(payload, opts)
          if @confirm_select
            multiple = false
            nack = false
            @confirm_select.call @next_publish_seq_no, multiple, nack
          end

          @server.publish payload, opts

          @next_publish_seq_no += 1 if @next_publish_seq_no > 0
        end
      end

      class Exchange
        def initialize(server, channel)
          @server = server
          @channel = channel
        end

        def publish(payload, opts)
          @channel.publish payload, opts
        end
      end

      class Queue
        attr_reader :name

        def initialize(name, server:, **opts)
          @name   = name
          @server = server
        end

        def subscribe(opts = {}, &block)
          @server.add_queue_subscriber @name, block
        end
      end

    end # class LoopbackServer
  end # module Testing
end # module Fluffle
