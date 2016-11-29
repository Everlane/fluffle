require 'spec_helper'

describe Fluffle::Server do
  describe '#handle_request' do
    before do
      @exchange_spy = exchange_spy = spy 'Exchange'

      subject.instance_eval do
        @exchange = exchange_spy
      end
    end

    def id
      @id = '123' unless instance_variable_defined? :@id
      @id
    end

    def method
      @method = 'do_something' unless instance_variable_defined? :@method
      @method
    end

    def params
      @params = [] unless instance_variable_defined? :@params
      @params
    end

    def reply_to
      @reply_to = 'fakeclient' unless instance_variable_defined? :@reply_to
      @reply_to
    end

    def make_request(payload: {}, handler:)
      payload['jsonrpc'] = '2.0'  unless payload.key? 'jsonrpc'
      payload['id']      = id     unless payload.key? 'id'
      payload['method']  = method unless payload.key? 'method'
      payload['params']  = params unless payload.key? 'params'

      subject.handle_request handler: handler,
                             properties: { reply_to: reply_to },
                             payload: Oj.dump(payload)
    end

    def expect_response(payload:, routing_key: nil, correlation_id: nil)
      routing_key    ||= reply_to
      correlation_id ||= id

      payload['jsonrpc'] ||= '2.0'
      payload['id']      ||= id

      expect(@exchange_spy).to have_received(:publish) do |payload_json, opts|
        expect(Oj.load(payload_json)).to include payload

        expect(opts).to eq routing_key: routing_key,
                           correlation_id: correlation_id
      end
    end

    it 'responds with the result for a normal request' do
      @params = ['bar']

      result = 'baz'

      handler = double 'Handler'
      expect(handler).to receive(:call) do |args|
        expect(args).to eq({
          id: id,
          method: method,
          params: params,
          meta: {}
        })

        result
      end

      make_request handler: handler

      expect_response payload: { 'result' => result }
    end

    it 'responds with the appropriate code and message when method not found' do
      @method = 'notfound'

      handler = double 'Handler'
      expect(handler).to receive(:call).and_raise(NoMethodError.new("undefined method `#{method}'"))

      make_request handler: handler

      expect_response payload: {
                        'error' => {
                          'code'    => -32601,
                          'message' => 'Method not found'
                        }
                      }
    end

    it "responds with the appropriate code and message when `method' isn't supplied" do
      @method = nil

      handler = double 'Handler'
      expect(handler).not_to receive(:call)

      make_request handler: handler

      expect_response payload: {
                        'error' => {
                          'code' => -32600,
                          'message' => 'Invalid Request',
                          'data' => { 'description' => "Missing `method' Request object member" }
                        }
                      }
    end

    it 'includes appropriate meta-data in the response' do
      handler = double 'Handler'
      expect(handler).to receive(:call) do |args|
        sleep 0.01

        'Hello world!'
      end

      make_request handler: handler

      expect(@exchange_spy).to have_received(:publish) do |payload_json, opts|
        payload = Oj.load payload_json
        meta    = payload['meta']

        expect(meta['handler_duration']).to be >= 0.01
      end
    end

    it "calls the handler's #after_response method if defined" do
      @params = ['foo']

      result = 'bar'
      handler = double 'Handler'
      expect(handler).to receive(:call).ordered.and_return(result)

      expect(handler).to receive(:after_response).ordered do |opts|
        expect(opts[:request]).to include({
          'params' => @params,
        })
      end

      make_request handler: handler

      expect_response payload: { 'result' => result }
    end
  end
end
