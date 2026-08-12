class Source < ApplicationRecord
  # Generates a unique, URL-safe token used in the ingest URL (/in/:token).
  has_secure_token

  has_many :events, dependent: :destroy
end
