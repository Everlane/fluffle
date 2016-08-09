require 'bunny'

require 'fluffle/version'
require 'fluffle/client'
require 'fluffle/errors'
require 'fluffle/handlers/base'
require 'fluffle/handlers/delegator'
require 'fluffle/handlers/dispatcher'
require 'fluffle/server'

module Fluffle
  # Expand a short name into a fully-qualified one
  def self.request_queue_name(name)
    "fluffle.requests.#{name}"
  end

  def self.response_queue_name(name)
    "fluffle.responses.#{name}"
  end
end
