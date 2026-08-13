# Performs a single delivery attempt: POST the event to the destination, record
# the outcome as a DeliveryAttempt, and resolve the Delivery's status. Retrying
# failures with backoff arrives in M3.
class DeliveryJob < ApplicationJob
  queue_as :default

  MAX_RESPONSE_BODY = 10_000

  def perform(delivery)
    event = delivery.event
    result = WebhookClient.post(
      delivery.destination.url,
      body: event.body,
      content_type: event.content_type,
      headers: {
        "X-Hookrelay-Event" => event.id.to_s,
        "X-Hookrelay-Delivery" => delivery.id.to_s
      }
    )

    delivery.delivery_attempts.create!(
      status_code: result.status_code,
      response_body: result.body&.truncate(MAX_RESPONSE_BODY),
      duration_ms: result.duration_ms,
      error: result.error
    )
    delivery.update!(status: result.success? ? :succeeded : :failed)
  end
end
