# fluffle

[![Build Status](https://travis-ci.org/Everlane/fluffle.svg?branch=master)](https://travis-ci.org/Everlane/fluffle)

An implementation of [JSON-RPC][] over RabbitMQ through the [Bunny][] library. Provides both a client and server.

![](fluffle.jpg)

> A group of baby bunnies is called a [fluffle][].

[Bunny]: https://github.com/ruby-amqp/bunny
[fluffle]: http://imgur.com/6eABy1v
[JSON-RPC]: http://www.jsonrpc.org/specification

## Features

Both the client and server implementations should be thread-safe, as their behavior is implemented on top of the excellent [concurrent-ruby][] gem's data structures.

- Client: Thread-safe client that can perform multiple requests concurrently
- Server: Single or multi-threaded server (one request/response per thread)
- Server: Easy-to-use built-in handlers and straightforward API for building custom handlers

[concurrent-ruby]: https://github.com/ruby-concurrency/concurrent-ruby

## Examples

See the [`examples`](examples/) directory.

The server provides a few options for handling RPC requests:

- [Dispatcher](lib/fluffle/handlers/dispatcher.rb): `dispatcher.handle('upcase') { |str| str.upcase }`
- [Delegator](lib/fluffle/handlers/delegator.rb): delegate will receive the `#upcase` message with a single argument (the string)
- Custom: any handler needs to implement the API described in [`Fluffle::Handlers::Base`](lib/fluffle/handlers/base.rb)

### Basic server and client

A server has two basic requirements: the URL of a RabbitMQ server to connect to and one or more queues to drain (with a handler for each queue).

Below is a basic server providing an `upcase` method to return the upper cased version of its argument:

```ruby
require 'fluffle'

server = Fluffle::Server.new url: 'amqp://localhost'

server.drain do |dispatcher|
  dispatcher.handle('upcase') { |str| str.upcase }
end

server.start
```

This example relies on a couple features of `Server#drain`:

1. By default it will drain the `default` queue.
2. You can provide a block to the method to have it set up a [`Dispatcher`](lib/fluffle/handlers/dispatcher.rb) handler and pass that in to the block.

And client to call that `upcase` method looks like:

```ruby
client = Fluffle::Client.new url: 'amqp://localhost'

client.call 'upcase', ['Hello world!']
# => "HELLO WORLD!"
```

## License

Released under the MIT license, see [LICENSE](LICENSE) for details.
