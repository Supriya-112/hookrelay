ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "webmock/minitest"

# No real outbound HTTP in tests; delivery targets are stubbed per test.
WebMock.disable_net_connect!(allow_localhost: true)

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Runs the block with the inspector behind a password, as a deployment that
    # sets HOOKRELAY_INSPECTOR_USER and _PASSWORD has it.
    def with_inspector_password(user: "watcher", password: "s3cret")
      hookrelay = Rails.configuration.x.hookrelay
      was = hookrelay.inspector_credentials
      hookrelay.inspector_credentials = { user: user, password: password }
      yield user, password
    ensure
      hookrelay.inspector_credentials = was
    end

    # Runs the block with DestinationGuard enforcing, the way any deployment other
    # than local development has it.
    def with_private_destinations_refused
      hookrelay = Rails.configuration.x.hookrelay
      was_allowed = hookrelay.allow_private_destinations
      hookrelay.allow_private_destinations = false
      yield
    ensure
      hookrelay.allow_private_destinations = was_allowed
    end
  end
end
