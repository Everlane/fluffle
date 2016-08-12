module Fluffle
  module Connectable
    def self.included(klass)
      klass.class_eval do
        attr_reader :connection
      end
    end

    def connect(*args)
      self.stop if self.connected?

      @connection = Bunny.new *args
      @connection.start
    end

    def connected?
      @connection && @connection.connected?
    end
  end
end
