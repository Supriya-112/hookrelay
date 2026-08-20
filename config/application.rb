require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Hookrelay
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Deliveries to loopback and private addresses are refused (see
    # DestinationGuard). Local development delivers to sinks on the same machine,
    # so docker-compose.yml opts out; anything reachable from the internet should
    # not.
    config.x.hookrelay.allow_private_destinations = ENV["HOOKRELAY_ALLOW_PRIVATE_DESTINATIONS"] == "true"

    # Keys for the encrypted signing secrets, from the environment in every
    # environment so none of them sits in this repository looking like a real one.
    # docker-compose.yml and the CI workflow pass throwaway values for development
    # and test; a deployment passes keys made with `bin/rails db:encryption:init`.
    config.active_record.encryption.primary_key = ENV["AR_ENCRYPTION_PRIMARY_KEY"]
    config.active_record.encryption.deterministic_key = ENV["AR_ENCRYPTION_DETERMINISTIC_KEY"]
    config.active_record.encryption.key_derivation_salt = ENV["AR_ENCRYPTION_KEY_DERIVATION_SALT"]
  end
end
