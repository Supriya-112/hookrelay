require "test_helper"

# The two things that keep ingest from being a way to fill the database: a cap on
# how much one request may carry, and a limit on how often requests may come.
class IngestLimitsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup { @source = create_source(name: "GitHub") }

  test "a body within the cap is stored" do
    post_body "x" * (Rails.configuration.x.hookrelay.max_body_bytes - 1)

    assert_response :accepted
    assert_equal 1, @source.events.count
  end

  test "a body over the cap is refused and stored nowhere" do
    assert_no_difference -> { Event.count } do
      post_body "x" * (Rails.configuration.x.hookrelay.max_body_bytes + 1)
    end

    assert_response :content_too_large
  end

  test "a source that goes over its limit is asked to come back later" do
    limit = Rails.configuration.x.hookrelay.source_rate_limit

    limit.times { post_body "{}" }
    assert_response :accepted

    post_body "{}"

    assert_response :too_many_requests
    assert_equal Rails.configuration.x.hookrelay.rate_limit_period.to_i.to_s, response.headers["Retry-After"]
    assert_equal limit, @source.events.count, "nothing past the limit is stored"
  end

  test "one busy source doesn't spend another's allowance" do
    quiet = create_source(name: "Stripe")
    Rails.configuration.x.hookrelay.source_rate_limit.times { post_body "{}" }

    post ingest_path(quiet.token), params: "{}", headers: { "Content-Type" => "application/json" }

    assert_response :accepted
  end

  test "an unknown token is limited on its own account, not the whole site's" do
    # Deliberate: made-up tokens each get their own bucket, so this endpoint stays
    # predictable for real providers. Limiting a flood of nonsense URLs is the
    # edge's job, not something to fake here.
    limit = Rails.configuration.x.hookrelay.source_rate_limit

    (limit + 1).times { post "/in/made-up", params: "{}", headers: { "Content-Type" => "application/json" } }
    assert_response :too_many_requests

    post ingest_path(@source.token), params: "{}", headers: { "Content-Type" => "application/json" }
    assert_response :accepted
  end

  private

  def post_body(body)
    post ingest_path(@source.token), params: body, headers: { "Content-Type" => "text/plain" }
  end
end
