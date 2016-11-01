lib = File.join File.dirname(__FILE__), '..', 'lib'
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'fluffle'

server = Fluffle::Server.new url: 'amqp://localhost', concurrency: 5, confirms: true, mandatory: true

server.drain do |dispatcher|
  dispatcher.handle('foo') { 'bar' }
end

server.start
