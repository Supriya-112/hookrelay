require "test_helper"

class IngestTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "enqueues delivery for the received event" do
    source = Source.create!(name: "GitHub")

    assert_enqueued_with(job: DeliverEventJob) do
      post ingest_path(source.token), params: "{}", headers: { "Content-Type" => "application/json" }
    end
  end

  test "stores an incoming webhook and acknowledges with 202" do
    source = Source.create!(name: "GitHub")
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
    source = Source.create!(name: "GitHub")
    payload = "\x1f\x8b\x08\x00\x00\x00\x00\x00binary\xC3\x28".b

    post ingest_path(source.token), params: payload, headers: { "Content-Type" => "application/octet-stream" }

    assert_response :accepted
    assert_equal payload, source.events.last.body.b
  end

  test "an unknown token is rejected and stores nothing" do
    assert_no_difference -> { Event.count } do
      post "/in/does-not-exist", params: "x"
    end

    assert_response :not_found
  end
end
