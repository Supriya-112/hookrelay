require "test_helper"

class DeliveryJobTest < ActiveJob::TestCase
  test "a 2xx response marks the delivery succeeded and records the attempt" do
    delivery = build_delivery("https://ok.example.com/hook")
    stub = stub_request(:post, "https://ok.example.com/hook").to_return(status: 200, body: "thanks")

    DeliveryJob.perform_now(delivery)

    assert_requested stub
    assert delivery.reload.succeeded?
    attempt = delivery.delivery_attempts.sole
    assert_equal 200, attempt.status_code
    assert_equal "thanks", attempt.response_body
    assert_nil attempt.error
  end

  test "a non-2xx response marks the delivery failed and records the status code" do
    delivery = build_delivery("https://bad.example.com/hook")
    stub_request(:post, "https://bad.example.com/hook").to_return(status: 500, body: "nope")

    DeliveryJob.perform_now(delivery)

    assert delivery.reload.failed?
    assert_equal 500, delivery.delivery_attempts.sole.status_code
  end

  test "a connection failure is recorded as an error with no status code" do
    delivery = build_delivery("https://down.example.com/hook")
    stub_request(:post, "https://down.example.com/hook").to_timeout

    DeliveryJob.perform_now(delivery)

    assert delivery.reload.failed?
    attempt = delivery.delivery_attempts.sole
    assert_nil attempt.status_code
    assert attempt.error.present?
  end

  test "forwards the event body and hookrelay headers to the destination" do
    delivery = build_delivery("https://ok.example.com/hook")
    stub = stub_request(:post, "https://ok.example.com/hook")
             .with(body: "the-payload", headers: { "X-Hookrelay-Event" => delivery.event.id.to_s })
             .to_return(status: 200)

    DeliveryJob.perform_now(delivery)

    assert_requested stub
  end

  test "reschedules a later attempt when the delivery fails" do
    delivery = build_delivery("https://bad.example.com/hook")
    stub_request(:post, "https://bad.example.com/hook").to_return(status: 500)

    assert_enqueued_with(job: DeliveryJob) do
      DeliveryJob.perform_now(delivery)
    end

    delivery.reload
    assert delivery.failed?
    assert delivery.next_attempt_at.present?
    assert_equal 1, delivery.attempts_count
  end

  test "dead-letters after the maximum number of attempts" do
    delivery = build_delivery("https://bad.example.com/hook")
    (DeliveryJob::MAX_ATTEMPTS - 1).times { delivery.delivery_attempts.create!(status_code: 500) }
    stub_request(:post, "https://bad.example.com/hook").to_return(status: 500)

    assert_no_enqueued_jobs only: DeliveryJob do
      DeliveryJob.perform_now(delivery)
    end

    delivery.reload
    assert delivery.dead?
    assert_equal DeliveryJob::MAX_ATTEMPTS, delivery.attempts_count
    assert_nil delivery.next_attempt_at
  end

  test "does nothing for an already-resolved delivery" do
    delivery = build_delivery("https://ok.example.com/hook")
    delivery.update!(status: :succeeded)

    # No stub: if it tried to POST, WebMock (net connect disabled) would raise.
    assert_no_difference -> { delivery.delivery_attempts.count } do
      DeliveryJob.perform_now(delivery)
    end
  end

  test "retry_delay grows with the attempt and stays within bounds" do
    assert_operator DeliveryJob.retry_delay(1).to_i, :<=, 5
    assert DeliveryJob.retry_delay(3).to_i.between?(10, 20)
    assert_operator DeliveryJob.retry_delay(20).to_i, :<=, 3600
  end

  private

  def build_delivery(url)
    source = Source.create!(name: "GitHub")
    event = source.events.create!(http_method: "POST", content_type: "application/json", headers: {}, body: "the-payload")
    destination = source.destinations.create!(url: url)
    Delivery.create!(event: event, destination: destination)
  end
end
