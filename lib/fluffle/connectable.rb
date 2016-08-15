module Fluffle
  module Connectable
    def self.included(klass)
      klass.class_eval do
        attr_reader :connection
      end
    end

    def connect(*args)
      self.stop if self.connected?

      @connection =
        if args.first.is_a? Bunny::Session
          args.first
        else
          Bunny.new *args
        end

      @connection.start
    end

    def connected?
      @connection && @connection.connected?
    end
  end
end
