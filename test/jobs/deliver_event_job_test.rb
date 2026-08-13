require "test_helper"

class DeliverEventJobTest < ActiveJob::TestCase
  test "creates a delivery per destination and enqueues a delivery job for each" do
    source = Source.create!(name: "GitHub")
    event = source.events.create!(http_method: "POST", headers: {}, body: "{}")
    source.destinations.create!(url: "https://a.example.com/hook")
    source.destinations.create!(url: "https://b.example.com/hook")

    assert_difference -> { Delivery.count }, 2 do
      assert_enqueued_jobs 2, only: DeliveryJob do
        DeliverEventJob.perform_now(event)
      end
    end
  end

  test "does not duplicate deliveries when run again for the same event" do
    source = Source.create!(name: "GitHub")
    event = source.events.create!(http_method: "POST", headers: {}, body: "{}")
    source.destinations.create!(url: "https://a.example.com/hook")

    DeliverEventJob.perform_now(event)

    assert_no_difference -> { Delivery.count } do
      DeliverEventJob.perform_now(event)
    end
  end
end
