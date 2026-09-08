require "test_helper"

class IngestTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "enqueues delivery for the received event" do
    source = create_source(name: "GitHub")

    assert_enqueued_with(job: DeliverEventJob) do
      post ingest_path(source.token), params: "{}", headers: { "Content-Type" => "application/json" }
    end
  end

  test "stores an incoming webhook and acknowledges with 202" do
    source = create_source(name: "GitHub")
    payload = { "event" => "push", "id" => 42 }.to_json

    assert_difference -> { source.events.count }, 1 do
      post ingest_path(source.token),
        params: payload,
        headers: { "Content-Type" => "application/json", "X-Test" => "abc" }
    end

    assert_response :accepted
    event = source.events.last
    assert_equal "POST", event.http_method
    assert_equal payload, event.body
    assert_equal "application/json", event.content_type
    assert_equal "abc", event.headers["X-Test"]
  end

  test "accepts a body that is not text, such as a gzipped payload" do
    source = create_source(name: "GitHub")
    payload = "\x1f\x8b\x08\x00\x00\x00\x00\x00binary\xC3\x28".b

    post ingest_path(source.token), params: payload, headers: { "Content-Type" => "application/octet-stream" }

    assert_response :accepted
    assert_equal payload, source.events.last.body.b
  end

  test "accepts a sender whose user agent looks like an ancient browser" do
    source = create_source(name: "GitHub")

    assert_difference -> { source.events.count }, 1 do
      post ingest_path(source.token),
        params: "{}",
        headers: { "Content-Type" => "application/json", "User-Agent" => "Mozilla/5.0 (compatible; MSIE 9.0; Windows NT 6.1)" }
    end

    assert_response :accepted
  end

  test "a source that verifies signatures stores a correctly signed webhook" do
    source = create_source(name: "GitHub", signature_scheme: "github", signing_secret: "whsec_1")
    payload = '{"event":"push"}'

    assert_difference -> { source.events.count }, 1 do
      post ingest_path(source.token), params: payload, headers: {
        "Content-Type" => "application/json",
        "X-Hub-Signature-256" => "sha256=#{OpenSSL::HMAC.hexdigest("SHA256", "whsec_1", payload)}"
      }
    end

    assert_response :accepted
  end

  test "a wrongly signed webhook is refused and stores nothing" do
    source = create_source(name: "GitHub", signature_scheme: "github", signing_secret: "whsec_1")

    assert_no_difference -> { Event.count } do
      post ingest_path(source.token), params: '{"event":"push"}', headers: {
        "Content-Type" => "application/json",
        "X-Hub-Signature-256" => "sha256=#{"0" * 64}"
      }
    end

    assert_response :unauthorized
  end

  test "an unsigned webhook is refused when the source expects signatures" do
    source = create_source(name: "GitHub", signature_scheme: "github", signing_secret: "whsec_1")

    assert_no_difference -> { Event.count } do
      post ingest_path(source.token), params: "{}", headers: { "Content-Type" => "application/json" }
    end

    assert_response :unauthorized
  end

  test "a provider retrying the same delivery gets the first event back" do
    source = create_source(name: "GitHub")

    assert_difference -> { source.events.count }, 1 do
      2.times { post_signed_delivery(source, delivery: "abc-123") }
    end

    assert_response :accepted
    assert response.parsed_body["duplicate"], "the second answer says it's a repeat"
    assert_equal source.events.sole.id, response.parsed_body["event_id"]
  end

  test "a retry is not delivered a second time" do
    source = create_source(name: "GitHub")
    source.destinations.create!(url: "https://example.com/hook")

    assert_enqueued_jobs 1, only: DeliverEventJob do
      2.times { post_signed_delivery(source, delivery: "abc-123") }
    end
  end

  test "different deliveries from the same provider are different events" do
    source = create_source(name: "GitHub")

    assert_difference -> { source.events.count }, 2 do
      post_signed_delivery(source, delivery: "abc-123")
      post_signed_delivery(source, delivery: "def-456")
    end
  end

  test "a delivery id only counts within its own source" do
    a = create_source(name: "GitHub")
    b = create_source(name: "GitHub again")

    post_signed_delivery(a, delivery: "abc-123")
    post_signed_delivery(b, delivery: "abc-123")

    assert_response :accepted
    assert_not response.parsed_body["duplicate"]
    assert_equal 1, a.events.count
    assert_equal 1, b.events.count
  end

  test "a payload that claims to be JSON but isn't is still stored" do
    # The inspector exists to show what actually arrived, so a provider sending
    # broken JSON is exactly the case that must not be dropped.
    source = create_source(name: "GitHub")
    broken = '{"event":"push"'

    post ingest_path(source.token), params: broken, headers: { "Content-Type" => "application/json" }

    assert_response :accepted
    assert_equal broken, source.events.sole.body
  end

  test "a provider that names nothing gets an event per request" do
    source = create_source(name: "GitHub")

    assert_difference -> { source.events.count }, 2 do
      2.times { post ingest_path(source.token), params: "{}", headers: { "Content-Type" => "application/json" } }
    end

    assert_nil source.events.first.idempotency_key
  end

  test "an unknown token is rejected and stores nothing" do
    assert_no_difference -> { Event.count } do
      post "/in/does-not-exist", params: "x"
    end

    assert_response :not_found
  end

  private

  # GitHub names each delivery in X-Github-Delivery and repeats it when it retries.
  def post_signed_delivery(source, delivery:)
    post ingest_path(source.token), params: '{"event":"push"}', headers: {
      "Content-Type" => "application/json", "X-Github-Delivery" => delivery
    }
  end
end
