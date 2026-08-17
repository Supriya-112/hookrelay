class Event < ApplicationRecord
  belongs_to :source
  has_many :deliveries, dependent: :destroy

  # Headers whose value is a credential rather than metadata. That they arrived
  # is worth showing; their contents are not, since anyone who can read the
  # inspector would then hold the sender's key.
  REDACTED_HEADERS = %w[Authorization Proxy-Authorization Cookie X-Api-Key X-Auth-Token].freeze

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
