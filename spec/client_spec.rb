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

  describe '#initialize' do
    it 'allows user to pass an `amqp://` URL via `url:`' do
      client = Fluffle::Client.new url: 'amqp://localhost'

      expect(client.connection).to be_a Bunny::Session
      expect(client.connected?).to eq true
    end

    it 'allows user to provide existing Bunny connection via `connection:`' do
      bunny_channel = double 'Bunny::Channel',
        default_exchange: double('Bunny::Exchange'),
        queue: double('Bunny::Queue', subscribe: nil)

      bunny_session = double 'Bunny::Session',
        create_channel: bunny_channel,
        start: nil,
        connected?: true

      allow(bunny_session).to receive(:is_a?).with(Bunny::Session).and_return(true)

      client = Fluffle::Client.new connection: bunny_session

      expect(client.connection).to eq bunny_session
      expect(client.connected?).to eq true
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

    it 'accepts null as a result' do
      respond = prepare_response 'result' => nil

      allow(@exchange_spy).to receive(:publish) do |payload, _opts|
        respond.call Oj.load(payload)['id']
      end

      expect(subject.call('something')).to eq(nil)
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
