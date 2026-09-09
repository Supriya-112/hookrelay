class DeliveryAttempt < ApplicationRecord
  belongs_to :delivery

  # Same rule as #ok?, usable in a query — the one place that decides what
  # counts as a successful attempt.
  scope :successful, -> { where(status_code: WebhookClient::SUCCESS_STATUSES) }

  # Attempts are the point of the inspector: they show up under their delivery as
  # they happen, rendered in a job so the delivery worker isn't held up by it.
  after_create_commit -> {
    broadcast_append_later_to delivery.event,
      target: delivery.attempts_dom_id,
      partial: "delivery_attempts/delivery_attempt",
      locals: { delivery_attempt: self }
  }

  # A response arrived when status_code is set; otherwise error explains why not.
  def ok?
    WebhookClient::SUCCESS_STATUSES.cover?(status_code)
  end
end
