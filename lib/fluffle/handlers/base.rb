module Fluffle
  module Handlers
    class Base
      def call(method:, params:, id:, meta:)
        raise RuntimeError, '#call is not implemented on abstract Base handler class'
      end
    end
  end
end
