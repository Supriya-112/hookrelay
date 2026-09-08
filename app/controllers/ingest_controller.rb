# Receives webhooks from external providers. Each request is matched to a Source
# by the token in its URL and stored as an Event, then acknowledged immediately
# with 202 — delivery to destinations happens out of band.
class IngestController < ApplicationController
  # A provider has no account here and nothing to sign in with — the URL's token
  # is what identifies the source, and a signature is what vouches for the request
  # (see InboundSignature). Everything else in the app requires a session.
  allow_unauthenticated_access

  # Providers can't send a CSRF token, and there's no session here, so the
  # forgery check doesn't apply to this endpoint.
  skip_forgery_protection

  # Per source, so one provider having a bad day can't crowd out the others. This
  # is deliberately not also keyed by address: an address-based limit belongs at
  # the edge, where it sees the whole site and can't be sidestepped by rotating
  # the URL's token. Counting happens in the cache — Solid Cache in production, so
  # every process shares one tally.
  rate_limit to: Rails.configuration.x.hookrelay.source_rate_limit,
             within: Rails.configuration.x.hookrelay.rate_limit_period,
             by: -> { token }, name: "source", with: -> { too_many_requests }

  # Headers a provider uses to name a delivery, most explicit first. A retry of
  # the same webhook carries the same value, which is what tells a retry apart
  # from a new event; a provider that sends none of them gets no de-duplication.
  IDEMPOTENCY_HEADERS = %w[
    Idempotency-Key
    Webhook-Id
    X-Github-Delivery
    X-Shopify-Webhook-Id
    X-Svix-Id
  ].freeze

  # Rack keeps the protocol version in HTTP_VERSION alongside the real headers;
  # it was never something the sender set, so it isn't part of the event.
  RACK_PSEUDO_HEADERS = %w[HTTP_VERSION].freeze

  def create
    source = Source.find_by(token: token)
    return head :not_found unless source
    return head :content_too_large if too_large?
    return head :unauthorized unless signature_accepted?(source)

    event, stored = store(source)
    DeliverEventJob.perform_later(event) if stored

    render json: { event_id: event.id, duplicate: !stored }, status: :accepted
  end

  private

  # Read from the path rather than through `params`, which would parse the body:
  # a provider sending malformed JSON would then be answered with 400 by Rails
  # before reaching this controller, and the very payload someone opened the
  # inspector to look at would be the one thing not stored.
  def token
    request.path_parameters[:token]
  end

  # A provider retrying a delivery it already sent gets the first event back
  # rather than a second copy of it, and nothing is delivered twice.
  def store(source)
    key = idempotency_key
    existing = source.events.find_by(idempotency_key: key) if key.present?
    return [ existing, false ] if existing

    [ source.events.create!(**event_attributes(key)), true ]
  rescue ActiveRecord::RecordNotUnique
    # Two copies of the same delivery arrived together; the unique index settled
    # which one is the event, and this is the other one.
    [ source.events.find_by!(idempotency_key: key), false ]
  end

  def event_attributes(key)
    {
      http_method: request.request_method,
      content_type: request.media_type,
      headers: request_headers,
      body: request.raw_post,
      idempotency_key: key
    }
  end

  def idempotency_key
    IDEMPOTENCY_HEADERS.lazy.filter_map { |name| request.headers[name].presence }.first
  end

  # The cap is a backstop, not a shield: by the time this runs the body has been
  # read off the socket, so an edge proxy should have a limit of its own. Checking
  # the declared length first means the usual oversized request is refused without
  # looking at what it sent.
  def too_large?
    max = Rails.configuration.x.hookrelay.max_body_bytes
    declared = request.content_length

    return true if declared.present? && declared > max

    request.raw_post.bytesize > max
  end

  # A source with no scheme configured takes whatever reaches its URL; one that
  # expects signatures takes only what carries a valid one. A request that fails
  # the check is not stored — we can't say the provider sent it, and storing it
  # would let anyone who knows the URL fill the inspector.
  def signature_accepted?(source)
    return true unless source.verifies_signatures?

    InboundSignature.valid?(source, body: request.raw_post, headers: request.headers)
  end

  # Providers back off on their own schedule, but saying when we'll listen again
  # is cheap and some of them read it.
  def too_many_requests
    response.headers["Retry-After"] = Rails.configuration.x.hookrelay.rate_limit_period.to_i.to_s
    head :too_many_requests
  end

  # The sender's HTTP headers, pulled out of the Rack env (where they arrive as
  # HTTP_* keys) and turned back into their wire names, so we keep what was sent
  # without the rest of the server's environment.
  def request_headers
    request.headers.env.each_with_object({}) do |(key, value), headers|
      next unless key.start_with?("HTTP_") && value.is_a?(String)
      next if RACK_PSEUDO_HEADERS.include?(key)

      name = key.delete_prefix("HTTP_").split("_").map(&:capitalize).join("-")
      headers[name] = value
    end
  end
end
