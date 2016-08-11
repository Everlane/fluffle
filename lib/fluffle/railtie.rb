module Fluffle
  class Railtie < Rails::Railtie
    # Inherit the application's logger
    initializer 'fluffle.configure_logger', after: 'initialize_logger' do |app|
      Fluffle.logger = app.config.logger
    end
  end
end
