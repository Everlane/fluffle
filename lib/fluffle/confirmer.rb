module Fluffle
  class Confirmer
    attr_reader :channel

    def initialize(channel:)
      @channel = channel

      @pending_confirms = Concurrent::Map.new
    end

    # Enables confirms on the channel and sets up callback to receive and
    # unblock corresponding `with_confirmation` call.
    def confirm_select
      handle_confirm = ->(tag, _multiple, nack) do
        ivar = @pending_confirms.delete tag

        if ivar
          ivar.set nack
        else
          self.logger.error "Missing confirm IVar: tag=#{tag}"
        end
      end

      # Set the channel in confirmation mode so that we can receive confirms
      # of published messages
      @channel.confirm_select handle_confirm
    end

    # Wraps a block (which should publish a message) with a blocking check
    # that it received a confirmation from the RabbitMQ server that the
    # message that was received and routed successfully.
    def with_confirmation(timeout:)
      tag = @channel.next_publish_seq_no
      confirm_ivar = Concurrent::IVar.new
      @pending_confirms[tag] = confirm_ivar

      result = yield

      nack = confirm_ivar.value timeout
      if confirm_ivar.incomplete?
        raise Errors::ConfirmTimeoutError.new('Timed out waiting for confirm')
      elsif nack
        raise Errors::NackError.new('Received nack from confirmation')
      end

      result
    end
  end
end
