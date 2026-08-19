require "test_helper"

class SourceTest < ActiveSupport::TestCase
  test "generates a unique token on create" do
    a = Source.create!(name: "GitHub")
    b = Source.create!(name: "Stripe")

    assert a.token.present?
    assert_not_equal a.token, b.token
  end

  test "a signature scheme has to be one we can verify, and needs a secret" do
    assert_not Source.new(name: "x", signature_scheme: "hmac-of-my-own").valid?
    assert_not Source.new(name: "x", signature_scheme: "github").valid?, "a scheme without a secret verifies nothing"
    assert Source.new(name: "x", signature_scheme: "github", signing_secret: "whsec_1").valid?
    assert Source.new(name: "x").valid?, "no scheme means the source accepts anything"
  end

  test "verifies_signatures? needs both a scheme and a secret" do
    assert_not Source.new.verifies_signatures?
    assert_not Source.new(signing_secret: "whsec_1").verifies_signatures?
    assert Source.new(signature_scheme: "stripe", signing_secret: "whsec_1").verifies_signatures?
  end

  test "destroying a source destroys its events" do
    source = Source.create!(name: "GitHub")
    source.events.create!(http_method: "POST", headers: {}, body: "{}")

    assert_difference -> { Event.count }, -1 do
      source.destroy
    end
  end
end
