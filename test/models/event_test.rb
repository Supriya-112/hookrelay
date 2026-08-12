require "test_helper"

class EventTest < ActiveSupport::TestCase
  test "requires a source" do
    assert_not Event.new(http_method: "POST").valid?
  end

  test "is valid when attached to a source" do
    source = Source.create!(name: "GitHub")
    event = source.events.new(http_method: "POST", headers: {}, body: "{}")

    assert event.valid?
  end
end
