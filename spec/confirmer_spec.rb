require 'spec_helper'

describe Fluffle::Confirmer do
  class StubChannel
    attr_accessor :confirm_handler, :tag

    def initialize
      @tag = 1
    end

    def confirm_select(block = nil)
      @confirm_handler = block
    end

    def next_publish_seq_no
      @tag
    end
  end

  before do
    @channel = StubChannel.new
    @confirmer = Fluffle::Confirmer.new channel: @channel
  end

  describe '#with_confirmation' do
    let(:default_timeout) { 5 }

    before do
      @confirmer.confirm_select
    end

    it 'raises if it times out' do
      expect {
        @confirmer.with_confirmation(timeout: 0.001) { sleep 0.002 }
      }.to raise_error(Fluffle::Errors::ConfirmTimeoutError)
    end

    it 'raises if it receives a nack' do
      send_nack = -> {
        multiple = false
        nack = true
        @channel.confirm_handler.call @channel.tag, multiple, nack
      }

      expect {
        @confirmer.with_confirmation(timeout: default_timeout) {
          send_nack.call
        }
      }.to raise_error(Fluffle::Errors::NackError)
    end

    it 'returns the result if it receives an ack' do
      send_confirm = -> {
        multiple = false
        nack = false
        @channel.confirm_handler.call @channel.tag, multiple, nack
      }

      result = double 'result'

      expect(
        @confirmer.with_confirmation(timeout: default_timeout) {
          Thread.new {
            sleep 0.1
            send_confirm.call
          }

          sleep 0.2
          result
        }
      ).to eq result
    end
  end
end
