class DeliveryAttempt < ApplicationRecord
  belongs_to :delivery

  # A response arrived when status_code is set; otherwise error explains why not.
  def ok?
    WebhookClient::SUCCESS_STATUSES.cover?(status_code)
  end
end
