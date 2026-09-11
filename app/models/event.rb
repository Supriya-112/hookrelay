class Event < ApplicationRecord
  belongs_to :source
  has_many :deliveries, dependent: :destroy

  # Headers whose value is a credential rather than metadata. That they arrived
  # is worth showing; their contents are not, since anyone who can read the
  # inspector would then hold the sender's key.
  REDACTED_HEADERS = %w[Authorization Proxy-Authorization Cookie X-Api-Key X-Auth-Token].freeze

  # A source's page watches its stream, so a webhook that arrives while someone is
  # looking at it appears without a refresh. Rendering happens in a job to keep it
  # off the ingest request, which providers time out.
  after_create_commit -> { broadcast_prepend_later_to source, target: "events", partial: "events/event", locals: { event: self } }

  # Sends this event again to every destination its source has now. Deliveries
  # that already exist start over; a destination added since the event arrived
  # gets its first delivery from the fan-out, which also queues the work — so a
  # delivery is never handed two jobs for the same replay. Returns the deliveries
  # that were reset — reset_for_replay! itself decides whether a delivery a
  # worker is currently holding gets skipped, not a check made here first.
  def replay
    reset = deliveries.select(&:reset_for_replay!)
    DeliverEventJob.perform_later(self)
    reset
  end

  # The body is stored as bytes, so it comes back binary and may not be text at
  # all. Anything shown to a human goes through here: undecodable bytes become
  # replacement characters instead of breaking the view or the JSON encoder.
  def body_text
    body.to_s.dup.force_encoding(Encoding::UTF_8).scrub
  end

  # The received headers with credentials masked, for display.
  def display_headers
    headers.to_h { |name, value| [ name, redacted?(name) ? "[redacted]" : value ] }
  end

  private

  def redacted?(name)
    REDACTED_HEADERS.any? { |redacted| name.to_s.casecmp?(redacted) }
  end
end
