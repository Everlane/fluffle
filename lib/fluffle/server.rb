module Fluffle
  class Server
    class << self
      attr_accessor :default_server
    end

    attr_reader :connection, :queues

    def initialize(url: nil)
      self.connect(url) if url

      @queues = {}

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

      @queues[queue_name.to_s] = handler
    end
  end
end
