require "test_helper"

class InspectorTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include ActionCable::TestHelper
  test "the source list shows each source with its ingest URL and event count" do
    source = Source.create!(name: "GitHub")
    source.events.create!(http_method: "POST", headers: {}, body: "{}")

    get root_path

    assert_response :success
    assert_select "h1", "Sources"
    assert_select "a", "GitHub"
    assert_includes response.body, ingest_url(source.token)
    assert_includes response.body, "1"
  end

  test "the source list explains how to create one when there are none" do
    get root_path

    assert_response :success
    assert_select ".empty", /No sources yet/
  end

  test "a source page lists its destinations and events and subscribes to its stream" do
    source = Source.create!(name: "GitHub")
    source.destinations.create!(url: "https://example.com/hook")
    event = source.events.create!(http_method: "POST", content_type: "application/json", headers: {}, body: "{}")

    get source_path(source)

    assert_response :success
    assert_select "turbo-cable-stream-source"
    assert_select "code", text: "https://example.com/hook"
    assert_select "##{ActionView::RecordIdentifier.dom_id(event)}"
  end

  test "an event page shows its headers with credentials masked" do
    event = build_event(headers: { "Authorization" => "Bearer sk_live_secret", "X-Test" => "abc" })

    get event_path(event)

    assert_response :success
    assert_includes response.body, "[redacted]"
    assert_not_includes response.body, "sk_live_secret"
    assert_includes response.body, "abc"
  end

  test "an event page pretty-prints a JSON body" do
    event = build_event(content_type: "application/json", body: '{"event":"push","id":42}')

    get event_path(event)

    assert_response :success
    assert_select "pre.payload", /"event": "push"/
  end

  test "an event page renders a body that is not text" do
    event = build_event(content_type: "application/octet-stream", body: "\x1f\x8b\x08gzip\xC3\x28".b)

    get event_path(event)

    assert_response :success
    assert_select "pre.payload"
  end

  test "an event page lists each delivery with its attempts" do
    event = build_event
    destination = event.source.destinations.create!(url: "https://example.com/hook")
    delivery = Delivery.create!(event: event, destination: destination)
    delivery.delivery_attempts.create!(status_code: 500, duration_ms: 12, error: nil)
    delivery.update!(status: :failed, attempts_count: 1, next_attempt_at: 30.seconds.from_now)

    get event_path(event)

    assert_response :success
    assert_select "##{delivery.row_dom_id}" do
      assert_select ".pill-failed", "failed"
      assert_select "##{delivery.attempts_dom_id} .attempt.bad", 1
      assert_select ".attempt .code", "500"
    end
  end

  test "a received event is broadcast to the source's stream" do
    source = Source.create!(name: "GitHub")

    assert_enqueued_jobs 1, only: Turbo::Streams::ActionBroadcastJob do
      source.events.create!(http_method: "POST", headers: {}, body: "{}")
    end
  end

  test "the broadcast carries the rendered event, ready to prepend" do
    source = Source.create!(name: "GitHub")
    get source_path(source)
    stream = stream_subscribed_on_page

    event = nil
    broadcasts = capture_broadcasts(stream) do
      perform_enqueued_jobs do
        event = source.events.create!(http_method: "POST", content_type: "application/json", headers: {}, body: "{}")
      end
    end

    assert_equal 1, broadcasts.size
    assert_match %r{<turbo-stream action="prepend" target="events">}, broadcasts.sole
    assert_match ActionView::RecordIdentifier.dom_id(event), broadcasts.sole
  end

  test "an attempt is broadcast under its delivery on the event's stream" do
    event = build_event
    destination = event.source.destinations.create!(url: "https://example.com/hook")
    delivery = Delivery.create!(event: event, destination: destination)
    get event_path(event)
    stream = stream_subscribed_on_page

    broadcasts = capture_broadcasts(stream) do
      perform_enqueued_jobs { delivery.delivery_attempts.create!(status_code: 200, duration_ms: 9) }
    end

    assert broadcasts.any? { |message| message.include?(%(action="append" target="#{delivery.attempts_dom_id}")) }
  end

  test "inspector pages ask for a password when one is configured" do
    with_inspector_password do |user, password|
      get root_path
      assert_response :unauthorized

      get root_path, headers: { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials(user, password) }
      assert_response :success
    end
  end

  test "a wrong password is refused" do
    with_inspector_password do |user, _password|
      get root_path, headers: { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials(user, "wrong") }

      assert_response :unauthorized
    end
  end

  test "ingest stays open when the inspector is behind a password" do
    source = Source.create!(name: "GitHub")

    with_inspector_password do
      post ingest_path(source.token), params: "{}", headers: { "Content-Type" => "application/json" }
    end

    assert_response :accepted
  end

  test "the inspector asks for a modern browser" do
    # Removed from ApplicationController because it rejected webhook senders; the
    # inspector's own pages still want it.
    get root_path, headers: { "HTTP_USER_AGENT" => "Mozilla/5.0 (compatible; MSIE 9.0; Windows NT 6.1)" }

    assert_response :not_acceptable
  end

  private

  # The page subscribes with a signed stream name; verifying it back gives the
  # stream the models must broadcast to, so the two can't drift apart unnoticed.
  def stream_subscribed_on_page
    source_tag = css_select("turbo-cable-stream-source").sole
    Turbo::StreamsChannel.verified_stream_name(source_tag["signed-stream-name"])
  end

  def build_event(headers: {}, content_type: "application/json", body: "{}")
    Source.create!(name: "GitHub").events.create!(
      http_method: "POST", content_type: content_type, headers: headers, body: body
    )
  end
end
