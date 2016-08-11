module Fluffle
  module Handlers
    # Lightweight DSL for defining handler blocks for a given message
    #
    # Examples
    #
    #   dispatcher = Fluffle::Handlers::Dispatcher.new
    #   dispatcher.handle('upcase') { |str| str.upcase }
    #
    #   # Also exposed through the `Fluffle::Server#drain` method
    #   server.drain do |dispatcher|
    #     dispatcher.handle('upcase') { |str| str.upcase }
    #   end
    #
    class Dispatcher < Base
      def initialize
        @routes = []

        yield self if block_given?
      end

      # pattern - Right now just a String that 1-to-1 matches the `method`
      # block - Block to call with the `params`
      def handle(pattern, &block)
        @routes << [pattern, block]
      end

      def call(method:, params:,  **_)
        @routes.each do |(pattern, block)|
          next if pattern != method

          return block.call(*params)
        end

        raise NoMethodError, "Undefined method '#{method}'"
      end
    end
  end
end
