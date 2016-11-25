require 'spec_helper'

describe Fluffle::MiddlewareStack do
  describe '#call' do
    it 'calls the middleware in the correct order' do
      order = []

      middleware1 = ->(parent) {
        order.push :pre1
        result = parent.call
        order.push :post1
        result
      }

      middleware2 = ->(parent) {
        order.push :pre2
        result = parent.call
        order.push :post2
        result
      }

      result = double 'result'
      block = -> {
        order.push :block
        result
      }

      subject.push middleware1
      subject.push middleware2
      expect(subject.call(&block)).to eq result
      expect(order).to eq [
        :pre1,
        :pre2,
        :block,
        :post2,
        :post1,
      ]
    end
  end
end
