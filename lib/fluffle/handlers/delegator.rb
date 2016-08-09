module Fluffle
  module Handlers
    class Delegator < Base
      def initialize(delegated_object)
        @delegated_object = delegated_object
      end

      def call(method:, params:)
        @delegated_object.send method.to_sym, *params
      end
    end
  end
end
