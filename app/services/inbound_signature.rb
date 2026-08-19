require "openssl"

# Checks that a webhook really came from the provider it claims to come from.
# Providers each sign differently, so a source says which scheme to expect and
# holds the secret that provider was given.
#
# Signatures cover the raw body byte for byte, which is why ingest stores and
# verifies `request.raw_post` rather than anything parsed.
class InboundSignature
  # Stripe includes a timestamp in what it signs so an intercepted request can't
  # be replayed later. Anything further from now than this — in either direction,
  # since a forged timestamp can as easily be in the future — is refused.
  TOLERANCE = 5.minutes

  class << self
    def valid?(source, body:, headers:, now: Time.current)
      case source.signature_scheme
      when "github" then github?(source.signing_secret, body, headers["X-Hub-Signature-256"])
      when "stripe" then stripe?(source.signing_secret, body, headers["Stripe-Signature"], now)
      else false
      end
    end

    private

    # X-Hub-Signature-256: sha256=<hex hmac of the body>
    def github?(secret, body, header)
      return false if header.blank?

      matches?(header, "sha256=#{hmac(secret, body)}")
    end

    # Stripe-Signature: t=<unix time>,v1=<hex hmac of "<t>.<body>">, and during a
    # secret rotation more than one v1 — any of which may be the good one.
    def stripe?(secret, body, header, now)
      return false if header.blank?

      pairs = parse(header)
      timestamp = pairs.find { |name, _| name == "t" }&.last
      return false if timestamp.blank?
      return false if (now.to_i - timestamp.to_i).abs > TOLERANCE.to_i

      expected = hmac(secret, "#{timestamp}.#{body}")
      pairs.any? { |name, value| name == "v1" && matches?(value, expected) }
    end

    def parse(header)
      header.split(",").filter_map do |part|
        name, value = part.split("=", 2)
        [ name.strip, value ] if value.present?
      end
    end

    def hmac(secret, payload)
      OpenSSL::HMAC.hexdigest("SHA256", secret.to_s, payload.to_s)
    end

    def matches?(given, expected)
      ActiveSupport::SecurityUtils.secure_compare(given.to_s, expected)
    end
  end
end
