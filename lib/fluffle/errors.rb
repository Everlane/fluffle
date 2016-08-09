module Fluffle
  module Errors
    class BaseError < StandardError
      # Longer-form description that may be present in the `data` field of the
      # `Error` response object
      attr_reader :description

      def to_response
        {
          'code'    => self.code,
          'message' => self.message,
          'data'    => self.data
        }
      end

      def data
        { 'description' => @description }
      end
    end

    class InvalidRequestError < BaseError
      def initialize(description)
        @description = description

        super 'Invalid Request'
      end

      def code
        -32600
      end
    end
  end
end
