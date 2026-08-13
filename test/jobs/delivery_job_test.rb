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

  private

  def build_delivery(url)
    source = Source.create!(name: "GitHub")
    event = source.events.create!(http_method: "POST", content_type: "application/json", headers: {}, body: "the-payload")
    destination = source.destinations.create!(url: url)
    Delivery.create!(event: event, destination: destination)
  end
end
