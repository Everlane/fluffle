lib = File.join File.dirname(__FILE__), '..', 'lib'
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'fluffle'

client = Fluffle::Client.new url: 'amqp://localhost', confirms: true
# You can also pass `connection:` to use an existing Bunny connection:
#   Fluffle::Client.new(connection: Bunny.new('amqp://localhost', heartbeat: 2))

timings = 10.times.map do
  t0 = Time.now
  client.call('foo').inspect
  Time.now - t0
end

puts timings
