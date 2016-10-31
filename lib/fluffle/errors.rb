module Fluffle
  module Errors
    class BaseError < StandardError
      def to_response
        {
          'code'    => self.code,
          'message' => self.message,
          'data'    => self.data
        }
      end
    end

    class TimeoutError < StandardError
    end

    # Raised if it received a return from the server
    class ReturnError < StandardError
    end

    # Raise this within your own code to get an error that will be faithfully
    # translated into the code, message, and data member fields of the
    # spec's `Error` response object
    class CustomError < BaseError
      attr_accessor :code, :data

      def initialize(code: 0, message:, data: nil)
        @code = code
        @data = data

        super message
      end
    end

    # Superclass of all errors that may be raised within the server
    class ServerError < BaseError
      # Longer-form description that may be present in the `data` field of
      # the `Error` response object
      attr_reader :description

      def data
        { 'description' => @description }
      end
    end

    class InvalidRequestError < ServerError
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
