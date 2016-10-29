module Fluffle
  class MiddlewareStack
    def initialize
      @stack = []
    end

    def push(middleware)
      @stack << middleware
      self
    end

    alias_method :<<, :push

    # Calls the stack in LIFO order with the callable (passed as an object
    # receiving `#call` or an `&block`) being called last.
    def call(callable = nil, &block)
      callable ||= block

      @stack
        .inject(callable) { |previous, middleware|
          ->{ middleware.call(previous) }
        }
        .call
    end
  end
end
