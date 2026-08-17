require "test_helper"

class SweepStuckDeliveriesJobTest < ActiveJob::TestCase
  test "recovers a claim whose worker never reported back" do
    delivery = build_delivery
    stall(delivery)

    assert_enqueued_with(job: DeliveryJob) do
      SweepStuckDeliveriesJob.perform_now
    end

    delivery.reload
    assert delivery.failed?
    assert_equal 1, delivery.attempts_count
    assert_match "worker stopped", delivery.delivery_attempts.sole.error
  end

  test "leaves a claim alone while it still has time to report back" do
    delivery = build_delivery
    delivery.claim

    assert_no_enqueued_jobs only: DeliveryJob do
      SweepStuckDeliveriesJob.perform_now
    end

    assert_equal "delivering", delivery.reload.status
  end

  test "dead-letters an abandoned claim that has used up its attempts" do
    delivery = build_delivery
    (DeliveryJob::MAX_ATTEMPTS - 1).times { delivery.delivery_attempts.create!(status_code: 500) }
    stall(delivery)

    assert_no_enqueued_jobs only: DeliveryJob do
      SweepStuckDeliveriesJob.perform_now
    end

    assert delivery.reload.dead?
  end

  test "requeues a retry that is overdue" do
    delivery = build_delivery
    delivery.update!(status: :failed, attempts_count: 1, next_attempt_at: 2.minutes.ago)

    assert_enqueued_with(job: DeliveryJob, args: [ delivery ]) do
      SweepStuckDeliveriesJob.perform_now
    end
  end

  test "leaves a retry that is not due yet" do
    delivery = build_delivery
    delivery.update!(status: :failed, attempts_count: 1, next_attempt_at: 10.minutes.from_now)

    assert_no_enqueued_jobs only: DeliveryJob do
      SweepStuckDeliveriesJob.perform_now
    end
  end

  test "requeues a delivery whose first attempt was never enqueued" do
    delivery = build_delivery
    delivery.update!(created_at: 1.hour.ago)

    assert_enqueued_with(job: DeliveryJob, args: [ delivery ]) do
      SweepStuckDeliveriesJob.perform_now
    end
  end

  test "leaves a freshly created delivery to the job that was just enqueued for it" do
    build_delivery

    assert_no_enqueued_jobs only: DeliveryJob do
      SweepStuckDeliveriesJob.perform_now
    end
  end

  private

  def build_delivery
    source = Source.create!(name: "GitHub")
    event = source.events.create!(http_method: "POST", headers: {}, body: "{}")
    destination = source.destinations.create!(url: "https://ok.example.com/hook")
    Delivery.create!(event: event, destination: destination)
  end

  # A claim taken long enough ago that its worker is presumed gone.
  def stall(delivery)
    delivery.claim
    delivery.update_column(:updated_at, SweepStuckDeliveriesJob::CLAIM_TIMEOUT.ago - 1.minute)
  end
end
