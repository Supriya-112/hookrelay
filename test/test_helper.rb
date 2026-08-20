ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "test_helpers/session_test_helper"
require "webmock/minitest"

# No real outbound HTTP in tests; delivery targets are stubbed per test.
WebMock.disable_net_connect!(allow_localhost: true)

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Most tests care that a source belongs to some account, not which one.
    def create_source(account: nil, **attributes)
      account ||= Account.create!(name: "Test account")
      account.sources.create!(**attributes)
    end

    # An account with an owner who is signed in, for tests of the pages behind the
    # login. Integration tests get `sign_in_as` from SessionTestHelper.
    def sign_in_new_account(name: "Acme")
      account = Account.create!(name: name)
      user = account.users.create!(
        email_address: "owner-#{SecureRandom.hex(4)}@example.com",
        password: "password"
      )
      sign_in_as user
      account
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
