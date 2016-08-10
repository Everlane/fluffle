require 'spec_helper'

describe Fluffle::Client do
  subject do
    Fluffle::Client.new url: nil
  end

  before do
    @exchange_spy = exchange_spy = spy 'Exchange'

    subject.instance_eval do
      @exchange = exchange_spy
    end
  end

  describe '#call' do
    def prepare_response(payload)
      ->(id) do
        response_payload = { 'jsonrpc' => '2.0', 'id' => id }.merge(payload)

        subject.handle_reply delivery_info: double('DeliveryInfo'),
                             properties: double('Properties'),
                             payload: Oj.dump(response_payload)
      end
    end

    it 'returns the value on result from server' do
      method = 'foo'
      result = 'bar'

      respond = prepare_response 'result' => result

      allow(@exchange_spy).to receive(:publish) do |payload, opts|
        payload = Oj.load(payload)

        expect(payload).to include({
          'id'     => kind_of(String),
          'method' => method
        })

        respond.call payload['id']
      end

      expect(subject.call(method)).to eq(result)
    end

    it 'raises on error from server' do
      code    = 1337
      message = 'Uh-oh!'

      respond = prepare_response 'error' => {
        'code'    => code,
        'message' => message
      }

      allow(@exchange_spy).to receive(:publish) do |payload, _opts|
        payload = Oj.load(payload)

        respond.call payload['id']
      end

      expect { subject.call('will.raise') }.to raise_error do |error|
        expect(error).to be_a Fluffle::Errors::CustomError
        expect(error.code).to eq code
        expect(error.message).to eq message
        expect(error.data).to be_nil
      end
    end

    it 'raises on timeout' do
      allow(@exchange_spy).to receive(:publish)

      t0 = Time.now

      expect {
        subject.call 'whatever', timeout: 0.01
      }.to raise_error(Fluffle::Errors::TimeoutError)

      expect(Time.now - t0).to be < 0.1
    end
  end
end
