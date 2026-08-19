require "test_helper"

class ReplayTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include ActionCable::TestHelper

  test "the event page offers to replay the event and each delivery" do
    delivery = build_delivery

    get event_path(delivery.event)

    assert_response :success
    assert_select "form[action=?]", replay_event_path(delivery.event)
    assert_select "form[action=?]", replay_delivery_path(delivery)
  end

  test "replaying an event from the inspector queues it again and says so" do
    delivery = build_delivery
    delivery.update!(status: :dead, attempts_count: 5)

    assert_enqueued_with job: DeliverEventJob, args: [ delivery.event ] do
      post replay_event_path(delivery.event)
    end

    assert_redirected_to event_path(delivery.event)
    assert_equal "Replaying to 1 destination.", flash[:notice]
    assert delivery.reload.pending?
  end

  test "replaying an event with nowhere to deliver says that instead" do
    event = Source.create!(name: "GitHub").events.create!(http_method: "POST", headers: {}, body: "{}")

    post replay_event_path(event)

    assert_equal "This source has no destinations to deliver to.", flash[:notice]
  end

  test "replaying one delivery from the inspector queues only that delivery" do
    delivery = build_delivery
    delivery.update!(status: :succeeded, attempts_count: 1)

    assert_enqueued_with job: DeliveryJob, args: [ delivery ] do
      post replay_delivery_path(delivery)
    end

    assert_redirected_to event_path(delivery.event)
    assert_match "Replaying to https://example.com/hook", flash[:notice]
    assert delivery.reload.pending?
  end

  test "replaying a delivery that is on its way is refused and explained" do
    delivery = build_delivery
    delivery.claim

    assert_no_enqueued_jobs only: DeliveryJob do
      post replay_delivery_path(delivery)
    end

    assert_equal "That delivery is already on its way.", flash[:notice]
  end

  test "an event replay over the API answers with what it queued" do
    delivery = build_delivery

    post replay_event_path(delivery.event), as: :json

    assert_response :accepted
    body = response.parsed_body
    assert_equal delivery.event.id, body["event_id"]
    assert_equal 1, body["destinations"]
    assert_equal 1, body["deliveries_reset"]
  end

  test "a delivery replay over the API answers with the delivery's new state" do
    delivery = build_delivery
    delivery.update!(status: :dead, attempts_count: 5)

    post replay_delivery_path(delivery), as: :json

    assert_response :accepted
    assert_equal "pending", response.parsed_body["status"]
  end

  test "the API refuses to replay a delivery that is on its way" do
    delivery = build_delivery
    delivery.claim

    post replay_delivery_path(delivery), as: :json

    assert_response :conflict
    assert_equal "delivering", response.parsed_body["status"]
  end

  test "replaying is behind the inspector's password when one is set" do
    delivery = build_delivery

    with_inspector_password do |user, password|
      post replay_delivery_path(delivery), as: :json
      assert_response :unauthorized

      post replay_delivery_path(delivery), as: :json,
        headers: { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials(user, password) }
      assert_response :accepted
    end
  end

  test "a reset delivery is broadcast to the event's page" do
    delivery = build_delivery
    get event_path(delivery.event)
    stream = stream_subscribed_on_page

    broadcasts = capture_broadcasts(stream) do
      perform_enqueued_jobs(only: Turbo::Streams::ActionBroadcastJob) do
        post replay_delivery_path(delivery)
      end
    end

    assert broadcasts.any? { |message| message.include?(%(action="replace" target="#{delivery.row_dom_id}")) },
      "the delivery row should be redrawn where the page is watching"
  end

  private

  def build_delivery
    source = Source.create!(name: "GitHub")
    event = source.events.create!(http_method: "POST", content_type: "application/json", headers: {}, body: "{}")
    Delivery.create!(event: event, destination: source.destinations.create!(url: "https://example.com/hook"))
  end

  def stream_subscribed_on_page
    source_tag = css_select("turbo-cable-stream-source").sole
    Turbo::StreamsChannel.verified_stream_name(source_tag["signed-stream-name"])
  end
end
