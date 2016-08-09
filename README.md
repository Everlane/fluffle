# fluffle

An implementation of [JSON-RPC][] over RabbitMQ through the [Bunny][] library. Provides both a client and server.

![](fluffle.jpg)

> A group of baby bunnies is called a [fluffle][].

[Bunny]: https://github.com/ruby-amqp/bunny
[fluffle]: http://imgur.com/6eABy1v
[JSON-RPC]: http://www.jsonrpc.org/specification

## Features

- Client: Thread-safe blocking client (via [concurrent-ruby][])
- Server: One-thread-per-queue implementation (multi-threaded coming soon)
- Server: Easy-to-use built-in handlers and straightforward API for building custom handlers

[concurrent-ruby]: https://github.com/ruby-concurrency/concurrent-ruby

## Examples

See the [`examples`](examples/) directory.

The server provides a few options for handling RPC requests:

- Dispatcher pattern: `dispatcher.handle('upcase') { |str| str.upcase }`
- Delegator pattern: delegate will receive the `#upcase` message with a single argument (the string)
- Custom: any handler needs to implement the API described in `Fluffle::Handlers::Base`

## License

Released under the MIT license, see [LICENSE](LICENSE) for details.
