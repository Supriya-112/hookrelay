require "openssl"

# Signs what we deliver, so a destination can tell a Hookrelay delivery from
# anything else that finds its endpoint. The shape follows Stripe's, since it is
# the one most receivers already have code for: a timestamp inside the signed
# payload, so an intercepted delivery can't be replayed later.
#
#   X-Hookrelay-Signature: t=1755600000,v1=<hex hmac of "1755600000.<body>">
class OutboundSignature
  HEADER = "X-Hookrelay-Signature"

  def self.header_value(secret:, body:, timestamp: Time.current)
    seconds = timestamp.to_i
    digest = OpenSSL::HMAC.hexdigest("SHA256", secret.to_s, "#{seconds}.#{body}")
    "t=#{seconds},v1=#{digest}"
  end
end
