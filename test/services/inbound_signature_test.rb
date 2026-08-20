require "test_helper"

class InboundSignatureTest < ActiveSupport::TestCase
  SECRET = "whsec_provider_secret"
  BODY = '{"event":"push"}'

  test "a GitHub signature made with the secret is accepted" do
    source = source_for("github")

    assert InboundSignature.valid?(source, body: BODY, headers: { "X-Hub-Signature-256" => github_header(SECRET, BODY) })
  end

  test "a GitHub signature made with another secret is refused" do
    source = source_for("github")

    assert_not InboundSignature.valid?(source, body: BODY, headers: { "X-Hub-Signature-256" => github_header("wrong", BODY) })
  end

  test "a GitHub signature over a different body is refused" do
    source = source_for("github")
    header = github_header(SECRET, BODY)

    assert_not InboundSignature.valid?(source, body: '{"event":"tampered"}', headers: { "X-Hub-Signature-256" => header })
  end

  test "a missing GitHub header is refused" do
    source = source_for("github")

    assert_not InboundSignature.valid?(source, body: BODY, headers: {})
    assert_not InboundSignature.valid?(source, body: BODY, headers: { "X-Hub-Signature-256" => "" })
  end

  test "a Stripe signature within the tolerance is accepted" do
    source = source_for("stripe")
    now = Time.current

    assert InboundSignature.valid?(source, body: BODY, headers: { "Stripe-Signature" => stripe_header(SECRET, BODY, now) }, now: now)
  end

  test "a Stripe signature older than the tolerance is refused" do
    source = source_for("stripe")
    now = Time.current
    stale = stripe_header(SECRET, BODY, now - InboundSignature::TOLERANCE - 1.minute)

    assert_not InboundSignature.valid?(source, body: BODY, headers: { "Stripe-Signature" => stale }, now: now)
  end

  test "a Stripe signature timestamped in the future is refused" do
    source = source_for("stripe")
    now = Time.current
    ahead = stripe_header(SECRET, BODY, now + InboundSignature::TOLERANCE + 1.minute)

    assert_not InboundSignature.valid?(source, body: BODY, headers: { "Stripe-Signature" => ahead }, now: now)
  end

  test "a Stripe timestamp cannot be moved without breaking the signature" do
    source = source_for("stripe")
    now = Time.current
    signed = stripe_header(SECRET, BODY, now - 10.minutes)
    # Same digest, a timestamp inside the window: what a replay would look like.
    moved = signed.sub(/\At=\d+/, "t=#{now.to_i}")

    assert_not InboundSignature.valid?(source, body: BODY, headers: { "Stripe-Signature" => moved }, now: now)
  end

  test "one valid v1 among several is accepted, as during a secret rotation" do
    source = source_for("stripe")
    now = Time.current
    good = stripe_header(SECRET, BODY, now)
    header = "#{good},v1=#{"0" * 64}"

    assert InboundSignature.valid?(source, body: BODY, headers: { "Stripe-Signature" => header }, now: now)
  end

  test "a malformed Stripe header is refused rather than raising" do
    source = source_for("stripe")

    [ "garbage", "t=,v1=", "v1=abc", "t=#{Time.current.to_i}", "" ].each do |header|
      assert_not InboundSignature.valid?(source, body: BODY, headers: { "Stripe-Signature" => header }),
        "expected #{header.inspect} to be refused"
    end
  end

  test "a source with no scheme verifies nothing" do
    source = create_source(name: "GitHub")

    assert_not source.verifies_signatures?
    assert_not InboundSignature.valid?(source, body: BODY, headers: { "X-Hub-Signature-256" => github_header(SECRET, BODY) })
  end

  private

  def source_for(scheme)
    create_source(name: "provider", signature_scheme: scheme, signing_secret: SECRET)
  end

  def github_header(secret, body)
    "sha256=#{OpenSSL::HMAC.hexdigest("SHA256", secret, body)}"
  end

  def stripe_header(secret, body, timestamp)
    seconds = timestamp.to_i
    "t=#{seconds},v1=#{OpenSSL::HMAC.hexdigest("SHA256", secret, "#{seconds}.#{body}")}"
  end
end
