require 'spec_helper'

describe Fluffle::Handlers::Delegator do
  before do
    @delegated_object = double 'Delegated Object'

    @handler = Fluffle::Handlers::Delegator.new @delegated_object
  end

  it 'calls the method with the params on the delegated object' do
    param1 = 'One'
    param2 = 'Two'
    result = 'Three'

    expect(@delegated_object).to receive(:some_method)
      .with(param1, param2)
      .and_return(result)

    actual_result = @handler.call id: 'abc123',
                                  method: 'some_method',
                                  params: [param1, param2],
                                  meta: {}

    expect(actual_result).to eq(result)
  end
end
