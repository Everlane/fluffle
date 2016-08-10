lib = File.join File.dirname(__FILE__), '..', 'lib'
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'fluffle'
require 'fluffle/testing'

server = Fluffle::Server.new url: 'amqp://localhost'

server.drain do |dispatcher|
  dispatcher.handle('foo') { 'bar' }
end

server.start

client = Fluffle::Client.new url: 'amqp://localhost'

timings = 10.times.map do
  t0 = Time.now
  client.call('foo').inspect
  Time.now - t0
end

puts timings
