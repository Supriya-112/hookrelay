require "test_helper"

class ApiKeyTest < ActiveSupport::TestCase
  test "issuing returns the key once and stores only its digest" do
    account = Account.create!(name: "Acme")

    key = ApiKey.issue(account: account, name: "deploy script")

    assert key.token.start_with?(ApiKey::PREFIX)
    assert_equal ApiKey.digest(key.token), key.token_digest
    assert_not_equal key.token, key.token_digest
    assert_nil ApiKey.find(key.id).token, "the key itself is not kept"
  end

  test "two keys are never the same" do
    account = Account.create!(name: "Acme")

    assert_not_equal ApiKey.issue(account: account, name: "a").token,
                     ApiKey.issue(account: account, name: "b").token
  end

  test "authenticate finds the key behind a token, and nothing else" do
    key = ApiKey.issue(account: Account.create!(name: "Acme"), name: "deploy script")

    assert_equal key, ApiKey.authenticate(key.token)
    assert_nil ApiKey.authenticate("#{key.token}x")
    assert_nil ApiKey.authenticate(key.token_digest), "the digest is not a key"
    assert_nil ApiKey.authenticate(nil)
    assert_nil ApiKey.authenticate("")
  end

  test "revoking an account takes its keys with it" do
    account = Account.create!(name: "Acme")
    ApiKey.issue(account: account, name: "deploy script")

    assert_difference -> { ApiKey.count }, -1 do
      account.destroy
    end
  end
end
