require "test_helper"

# One account must not be able to reach — or learn the existence of — another's
# webhooks. Everything the inspector reads goes through Current.account, so the
# answer to asking for someone else's record is the same as asking for one that
# was never there.
class TenancyTest < ActionDispatch::IntegrationTest
  setup do
    @account = sign_in_new_account(name: "Ours")
    @theirs = Account.create!(name: "Theirs")
  end

  test "the source list shows only this account's sources" do
    create_source(account: @account, name: "Ours")
    create_source(account: @theirs, name: "Theirs")

    get root_path

    assert_select "a", "Ours"
    assert_select "a", { count: 0, text: "Theirs" }
  end

  test "another account's source, event and delivery are all not found" do
    source = create_source(account: @theirs, name: "Theirs")
    event = source.events.create!(http_method: "POST", headers: {}, body: "{}")
    delivery = Delivery.create!(event: event, destination: source.destinations.create!(url: "https://example.com/hook"))

    # Not found rather than forbidden: the answer is the same as for a record that
    # never existed, so nothing is learned by asking.
    get source_path(source)
    assert_response :not_found

    get event_path(event)
    assert_response :not_found

    post replay_delivery_path(delivery)
    assert_response :not_found
  end

  test "counts on the dashboard don't include another account's events" do
    ours = create_source(account: @account, name: "Ours")
    ours.events.create!(http_method: "POST", headers: {}, body: "{}")
    theirs = create_source(account: @theirs, name: "Theirs")
    3.times { theirs.events.create!(http_method: "POST", headers: {}, body: "{}") }

    get root_path

    assert_select "table.grid tbody tr", 1
    assert_select "td.num", "1"
  end

  test "api keys are listed and revoked per account" do
    theirs = ApiKey.issue(account: @theirs, name: "theirs")
    ours = ApiKey.issue(account: @account, name: "ours")

    get api_keys_path
    assert_select "td", "ours"
    assert_select "td", { count: 0, text: "theirs" }

    delete api_key_path(theirs)
    assert_response :not_found
    assert ApiKey.exists?(theirs.id)

    delete api_key_path(ours)
    assert_not ApiKey.exists?(ours.id)
  end

  test "a source's ingest URL keeps working whoever is signed in" do
    source = create_source(account: @theirs, name: "Theirs")

    # Ingest identifies the source by its token, not by who is looking at the app.
    post ingest_path(source.token), params: "{}", headers: { "Content-Type" => "application/json" }

    assert_response :accepted
    assert_equal 1, source.events.count
  end
end
