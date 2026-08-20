require "openssl"

# A credential for the API. Only the digest is stored: the key is shown once, when
# it is issued, and can't be recovered afterwards — the same deal a provider gives
# us for its webhook secrets. Digesting also means the lookup is an index hit on a
# value that is worth nothing to whoever reads the database.
class ApiKey < ApplicationRecord
  PREFIX = "hr_"

  belongs_to :account

  validates :name, presence: true

  # The key itself, set only on the instance that just issued it.
  attr_accessor :token

  def self.issue(account:, name:)
    token = "#{PREFIX}#{SecureRandom.alphanumeric(40)}"
    key = create!(account: account, name: name, token_digest: digest(token))
    key.token = token
    key
  end

  # The key a caller presented, or nil when it isn't one of ours.
  def self.authenticate(token)
    return nil if token.blank?

    find_by(token_digest: digest(token))
  end

  def self.digest(token)
    OpenSSL::Digest::SHA256.hexdigest(token)
  end
end
