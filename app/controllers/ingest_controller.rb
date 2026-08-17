# Receives webhooks from external providers. Each request is matched to a Source
# by the token in its URL and stored as an Event, then acknowledged immediately
# with 202 — delivery to destinations happens out of band (M2+).
class IngestController < ApplicationController
  # Providers can't send a CSRF token, and there's no session here, so the
  # forgery check doesn't apply to this endpoint.
  skip_forgery_protection

  # Rack keeps the protocol version in HTTP_VERSION alongside the real headers;
  # it was never something the sender set, so it isn't part of the event.
  RACK_PSEUDO_HEADERS = %w[HTTP_VERSION].freeze

  def create
    source = Source.find_by(token: params[:token])
    return head :not_found unless source

    event = source.events.create!(
      http_method: request.request_method,
      content_type: request.media_type,
      headers: request_headers,
      body: request.raw_post
    )
    DeliverEventJob.perform_later(event)
    render json: { event_id: event.id }, status: :accepted
  end

  private

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
