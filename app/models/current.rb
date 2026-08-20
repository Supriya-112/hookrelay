class Current < ActiveSupport::CurrentAttributes
  attribute :session, :api_key
  delegate :user, to: :session, allow_nil: true

  # Whoever is asking — someone signed in, or a script holding a key — is only
  # ever shown their own account's records.
  def account
    user&.account || api_key&.account
  end
end
