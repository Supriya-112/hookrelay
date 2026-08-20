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

  test "an unknown token is rejected and stores nothing" do
    assert_no_difference -> { Event.count } do
      post "/in/does-not-exist", params: "x"
    end

    assert_response :not_found
  end
end
