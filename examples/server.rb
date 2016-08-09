lib = File.join File.dirname(__FILE__), '..', 'lib'
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'fluffle'

server = Fluffle::Server.new url: 'amqp://localhost'

server.drain do |dispatcher|
  dispatcher.handle('foo') { 'bar' }
end

server.start
