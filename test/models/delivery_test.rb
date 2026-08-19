require "test_helper"

class DeliveryTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

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

  test "only one claim of the same delivery succeeds" do
    delivery = create_delivery

    assert delivery.claim
    assert_equal "delivering", delivery.reload.status
    # A second worker holding its own copy of the row gets nothing.
    assert_not Delivery.find(delivery.id).claim
  end

  test "a delivery waiting on a retry can be claimed again" do
    delivery = create_delivery
    delivery.update!(status: :failed, next_attempt_at: 1.minute.ago)

    assert delivery.claim
  end

  test "a finished delivery cannot be claimed" do
    delivery = create_delivery

    delivery.update!(status: :succeeded)
    assert_not delivery.claim

    delivery.update!(status: :dead)
    assert_not delivery.claim
  end

  test "replaying resets the outcome and queues the delivery again" do
    delivery = create_delivery
    delivery.delivery_attempts.create!(status_code: 500)
    delivery.update!(status: :dead, attempts_count: 5, next_attempt_at: nil)

    assert_enqueued_with job: DeliveryJob, args: [ delivery ] do
      assert delivery.replay
    end

    delivery.reload
    assert delivery.pending?
    assert_equal 0, delivery.attempts_count
    assert delivery.replayed?
    assert_equal 1, delivery.delivery_attempts.count
  end

  test "replaying a delivery a worker already holds is refused" do
    delivery = create_delivery
    delivery.claim

    assert_no_enqueued_jobs only: DeliveryJob do
      assert_not delivery.reload.replay
    end

    assert_equal "delivering", delivery.reload.status
  end

  test "claiming records when it happened so a stalled claim can be spotted" do
    delivery = create_delivery
    delivery.update!(updated_at: 1.hour.ago)

    delivery.claim

    assert_operator delivery.reload.updated_at, :>, 1.minute.ago
  end

  private

  def create_delivery
    source = Source.create!(name: "GitHub")
    event = source.events.create!(http_method: "POST", headers: {}, body: "{}")
    destination = source.destinations.create!(url: "https://example.com/hook")
    Delivery.create!(event: event, destination: destination)
  end
end
