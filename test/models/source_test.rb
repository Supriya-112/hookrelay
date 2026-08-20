require "test_helper"

class SourceTest < ActiveSupport::TestCase
  test "generates a unique token on create" do
    a = create_source(name: "GitHub")
    b = create_source(name: "Stripe")

    assert a.token.present?
    assert_not_equal a.token, b.token
  end

  test "a signature scheme has to be one we can verify, and needs a secret" do
    account = Account.create!(name: "Acme")

    assert_not account.sources.new(name: "x", signature_scheme: "hmac-of-my-own").valid?
    assert_not account.sources.new(name: "x", signature_scheme: "github").valid?, "a scheme without a secret verifies nothing"
    assert account.sources.new(name: "x", signature_scheme: "github", signing_secret: "whsec_1").valid?
    assert account.sources.new(name: "x").valid?, "no scheme means the source accepts anything"
  end

  test "belongs to an account" do
    assert_not Source.new(name: "orphan").valid?, "a source with no account belongs to nobody"
  end

  test "the signing secret is encrypted in the database" do
    source = create_source(name: "GitHub", signature_scheme: "github", signing_secret: "whsec_plain")

    stored = Source.connection.select_value("SELECT signing_secret FROM sources WHERE id = #{source.id}")

    assert_not_equal "whsec_plain", stored
    assert_not_includes stored, "whsec_plain"
    assert_equal "whsec_plain", source.reload.signing_secret, "and readable through the model"
  end

  test "verifies_signatures? needs both a scheme and a secret" do
    assert_not Source.new.verifies_signatures?
    assert_not Source.new(signing_secret: "whsec_1").verifies_signatures?
    assert Source.new(signature_scheme: "stripe", signing_secret: "whsec_1").verifies_signatures?
  end

  test "destroying a source destroys its events" do
    source = create_source(name: "GitHub")
    source.events.create!(http_method: "POST", headers: {}, body: "{}")

    assert_difference -> { Event.count }, -1 do
      source.destroy
    end
  end
end
