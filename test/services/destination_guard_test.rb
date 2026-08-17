require "test_helper"

class DestinationGuardTest < ActiveSupport::TestCase
  test "allows a destination that resolves to a public address" do
    with_private_destinations_refused do
      assert_nil DestinationGuard.blocked_reason("https://example.com/hook", addresses: [ "93.184.216.34" ])
    end
  end

  test "refuses loopback and private addresses given as literals" do
    with_private_destinations_refused do
      [
        "http://127.0.0.1/hook",
        "http://10.1.2.3/hook",
        "http://192.168.0.10/hook",
        "http://172.16.5.4/hook",
        "http://169.254.169.254/latest/meta-data",
        "http://0.0.0.0/hook",
        "http://[::1]/hook",
        "http://[fd00::1]/hook"
      ].each do |url|
        assert DestinationGuard.blocked_reason(url).present?, "expected #{url} to be refused"
      end
    end
  end

  test "refuses localhost by name, whatever it resolves to" do
    with_private_destinations_refused do
      assert_match "this machine", DestinationGuard.blocked_reason("http://localhost:4000/hook")
      assert_match "this machine", DestinationGuard.blocked_reason("http://sink.localhost/hook")
    end
  end

  test "refuses a public hostname that resolves into the private network" do
    with_private_destinations_refused do
      reason = DestinationGuard.blocked_reason("https://internal.example.com/hook", addresses: [ "10.0.0.5" ])

      assert_match "10.0.0.5", reason
    end
  end

  test "refuses an IPv4-mapped IPv6 address for a private host" do
    with_private_destinations_refused do
      assert DestinationGuard.blocked_reason("https://sneaky.example.com/hook", addresses: [ "::ffff:10.0.0.5" ]).present?
    end
  end

  test "allows a host that cannot be resolved and lets the request fail instead" do
    with_private_destinations_refused do
      assert_nil DestinationGuard.blocked_reason("https://nope.example.com/hook", addresses: [])
    end
  end

  test "reports a URL with no host rather than trying to deliver to it" do
    with_private_destinations_refused do
      assert_equal "no host to deliver to", DestinationGuard.blocked_reason("not-a-url")
    end
  end

  test "allows everything when private destinations are permitted" do
    # Development delivers to sinks on the same machine; this is that opt-out.
    assert_nil DestinationGuard.blocked_reason("http://127.0.0.1:4000/hook")
  end
end
