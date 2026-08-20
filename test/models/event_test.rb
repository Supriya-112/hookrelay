require "test_helper"

class EventTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "requires a source" do
    assert_not Event.new(http_method: "POST").valid?
  end

  test "is valid when attached to a source" do
    source = create_source(name: "GitHub")
    event = source.events.new(http_method: "POST", headers: {}, body: "{}")

    assert event.valid?
  end

  test "stores a body that is not valid UTF-8, byte for byte" do
    source = create_source(name: "GitHub")
    payload = "\x1f\x8b\x08\x00compressed\xC3\x28".b

    event = source.events.create!(http_method: "POST", content_type: "application/octet-stream", headers: {}, body: payload)

    assert_equal payload, event.reload.body.b
  end

  test "body_text replaces bytes that are not text so it can be displayed" do
    event = Event.new(body: "ok \xC3\x28".b)

    assert event.body_text.valid_encoding?
    assert_equal Encoding::UTF_8, event.body_text.encoding
    assert event.body_text.start_with?("ok ")
  end

  test "replaying resets every delivery and fans the event out again" do
    source = create_source(name: "GitHub")
    event = source.events.create!(http_method: "POST", headers: {}, body: "{}")
    resolved = Delivery.create!(event: event, destination: source.destinations.create!(url: "https://a.example.com/hook"))
    resolved.update!(status: :succeeded, attempts_count: 1)

    reset = nil
    assert_enqueued_with job: DeliverEventJob, args: [ event ] do
      reset = event.replay
    end

    assert_equal [ resolved ], reset
    assert resolved.reload.pending?
    assert_equal 0, resolved.attempts_count
  end

  test "replaying skips a delivery a worker is holding but still fans out" do
    source = create_source(name: "GitHub")
    event = source.events.create!(http_method: "POST", headers: {}, body: "{}")
    in_flight = Delivery.create!(event: event, destination: source.destinations.create!(url: "https://a.example.com/hook"))
    in_flight.claim

    assert_enqueued_with job: DeliverEventJob, args: [ event ] do
      assert_empty event.reload.replay
    end

    assert_equal "delivering", in_flight.reload.status
  end

  test "display_headers masks credentials and keeps everything else" do
    event = Event.new(headers: {
      "Authorization" => "Bearer sk_live_secret",
      "Cookie" => "session=abc",
      "X-Api-Key" => "key",
      "x-hub-signature-256" => "sha256=abc",
      "Content-Length" => "31"
    })

    headers = event.display_headers

    assert_equal "[redacted]", headers["Authorization"]
    assert_equal "[redacted]", headers["Cookie"]
    assert_equal "[redacted]", headers["X-Api-Key"]
    # A signature proves who sent the event and is worth seeing while debugging;
    # it isn't a credential the reader could reuse.
    assert_equal "sha256=abc", headers["x-hub-signature-256"]
    assert_equal "31", headers["Content-Length"]
  end
end
