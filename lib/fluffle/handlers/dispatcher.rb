module Fluffle
  module Handlers
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
