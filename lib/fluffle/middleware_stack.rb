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

    # Calls the stack in FIFO order with the callable (passed as an object
    # receiving `#call` or an `&block`) being called last.
    #
    # For example:
    #   stack.push 1
    #   stack.push 2
    #   stack.call 3
    #
    # Will be evaluated 1 -> 2 -> 3 -> 2 -> 1.
    def call(callable = nil, &block)
      callable ||= block

      @stack
        .reverse
        .inject(callable) { |previous, middleware|
          ->{ middleware.call(previous) }
        }
        .call
    end
  end
end
