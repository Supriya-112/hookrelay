class Source < ApplicationRecord
  # Generates a unique, URL-safe token used in the ingest URL (/in/:token).
  has_secure_token

  # The provider's secret, encrypted at rest: a database dump shouldn't hand over
  # the means to forge webhooks. It is never queried, only read to verify.
  encrypts :signing_secret

  belongs_to :account
  has_many :events, dependent: :destroy
  has_many :destinations, dependent: :destroy

  # How the provider sending to this source signs its requests. Left unset, the
  # source accepts anything that reaches its URL.
  SIGNATURE_SCHEMES = %w[github stripe].freeze

  validates :signature_scheme, inclusion: { in: SIGNATURE_SCHEMES }, allow_nil: true
  validates :signing_secret, presence: true, if: -> { signature_scheme.present? }

  # A source with both a scheme and a secret checks every request before storing
  # it; see InboundSignature.
  def verifies_signatures?
    signature_scheme.present? && signing_secret.present?
  end
end
