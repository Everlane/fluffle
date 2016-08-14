require 'spec_helper'

describe Fluffle::Handlers::Dispatcher do
  before do
    @handler = Fluffle::Handlers::Dispatcher.new

    @handler.handle('double_it') { |arg| arg * 2 }
  end

  it 'calls the method with the params on the delegated object' do
    result = @handler.call id: 'abc123',
                           method: 'double_it',
                           params: [2],
                           meta: {}

    expect(result).to eq(4)
  end

  it 'raises error if method not configured' do
    expect {
      @handler.call id: 'def456',
                    method: 'doesnt_exist',
                    params: ['whatever'],
                    meta: {}
    }.to raise_error(NoMethodError, /doesnt_exist/)
  end
end
