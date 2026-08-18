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
