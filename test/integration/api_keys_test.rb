require "test_helper"

class ApiKeysTest < ActionDispatch::IntegrationTest
  setup { @account = sign_in_new_account }

  test "creating a key shows it once and never again" do
    post api_keys_path, params: { name: "deploy script" }

    key = @account.api_keys.sole
    assert_redirected_to api_keys_path
    follow_redirect!

    assert_response :success
    assert_select "pre.payload", /\A#{ApiKey::PREFIX}/
    shown = css_select("pre.payload").sole.text
    assert_equal key.token_digest, ApiKey.digest(shown), "what's shown is the real key"

    # Come back and it's gone — only the digest was ever stored.
    get api_keys_path
    assert_select "pre.payload", false
    assert_select "td", "deploy script"
  end

  test "a key without a name still gets one" do
    post api_keys_path, params: { name: "" }

    assert_equal "API key", @account.api_keys.sole.name
  end

  test "revoking a key stops it working" do
    key = ApiKey.issue(account: @account, name: "deploy script")

    delete api_key_path(key)

    assert_redirected_to api_keys_path
    assert_nil ApiKey.authenticate(key.token)
  end

  test "the keys page needs a session of its own" do
    sign_out

    get api_keys_path

    assert_redirected_to new_session_path
  end
end
