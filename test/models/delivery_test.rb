require "test_helper"

class DeliveryTest < ActiveSupport::TestCase
  test "defaults to pending" do
    assert Delivery.new.pending?
  end

  test "is unique per event and destination" do
    source = Source.create!(name: "GitHub")
    event = source.events.create!(http_method: "POST", headers: {}, body: "{}")
    destination = source.destinations.create!(url: "https://example.com/hook")
    Delivery.create!(event: event, destination: destination)

    assert_not Delivery.new(event: event, destination: destination).valid?
  end
end
