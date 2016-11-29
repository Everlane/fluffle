module Fluffle
  module Handlers
    class Base
      def call(method:, params:, id:, meta:)
        raise RuntimeError, '#call is not implemented on abstract Base handler class'
      end

      # This is called *after* the server has published the response message
      # to the client's queue.
      # def after_response(request:)
      #   ...
      # end
    end
  end
end
