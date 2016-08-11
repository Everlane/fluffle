require 'bunny'
require 'logger'

require 'fluffle/version'
require 'fluffle/client'
require 'fluffle/errors'
require 'fluffle/handlers/base'
require 'fluffle/handlers/delegator'
require 'fluffle/handlers/dispatcher'
require 'fluffle/server'

module Fluffle
  class << self
    attr_writer :logger

    def logger
      @logger ||= Logger.new $stdout
    end

    # Expand a short name into a fully-qualified one
    def request_queue_name(name)
      "fluffle.requests.#{name}"
    end

    def response_queue_name(name)
      "fluffle.responses.#{name}"
    end
  end
end

require 'fluffle/railtie' if defined? Rails
