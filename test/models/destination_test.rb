require "test_helper"

class DestinationTest < ActiveSupport::TestCase
  test "requires an http(s) url" do
    source = Source.create!(name: "GitHub")

    assert_not source.destinations.new(url: "not-a-url").valid?
    assert_not source.destinations.new(url: nil).valid?
    assert source.destinations.new(url: "https://example.com/hook").valid?
  end
end
