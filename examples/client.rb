lib = File.join File.dirname(__FILE__), '..', 'lib'
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'fluffle'

client = Fluffle::Client.new url: 'amqp://localhost'

timings = 10.times.map do
  t0 = Time.now
  client.call('foo').inspect
  Time.now - t0
end

puts timings
