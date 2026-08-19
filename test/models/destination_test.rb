require "test_helper"

class DestinationTest < ActiveSupport::TestCase
  test "gets its own signing secret on create" do
    source = Source.create!(name: "GitHub")

    a = source.destinations.create!(url: "https://a.example.com/hook")
    b = source.destinations.create!(url: "https://b.example.com/hook")

    assert a.signing_secret.present?
    assert_not_equal a.signing_secret, b.signing_secret
  end

  test "requires an http(s) url" do
    source = Source.create!(name: "GitHub")

    assert_not source.destinations.new(url: "not-a-url").valid?
    assert_not source.destinations.new(url: nil).valid?
    assert source.destinations.new(url: "https://example.com/hook").valid?
  end
end
