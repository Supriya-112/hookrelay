class Destination < ApplicationRecord
  belongs_to :source
  has_many :deliveries, dependent: :destroy

  validates :url, presence: true
  validate :url_must_be_http

  private

  # Parse rather than regex-match: this rejects a prefix like "https://" followed
  # by a newline and junk, and confirms there's an actual host to deliver to.
  def url_must_be_http
    return if url.blank?

    parsed = URI.parse(url)
    errors.add(:url, "must be an http(s) URL") unless parsed.is_a?(URI::HTTP) && parsed.host.present?
  rescue URI::InvalidURIError
    errors.add(:url, "must be a valid URL")
  end
end
