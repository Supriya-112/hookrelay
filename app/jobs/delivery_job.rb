# Performs a single delivery attempt: POST the event to the destination and
# record the outcome as a DeliveryAttempt. On failure the delivery is retried
# with exponential backoff until the attempt budget runs out, after which it is
# dead-lettered.
class DeliveryJob < ApplicationJob
  queue_as :default

  MAX_ATTEMPTS = 5
  MAX_RESPONSE_BODY = 10_000

  def perform(delivery)
    # A scheduled retry can fire after the delivery already resolved (e.g. a
    # replay succeeded); never attempt a finished delivery again.
    return if delivery.succeeded? || delivery.dead?

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
    resolve(delivery, result)
  end

  # Exponential backoff (5s, 10s, 20s, …) capped at an hour, with equal jitter so
  # a burst of failures to one destination doesn't retry in lockstep.
  def self.retry_delay(attempt)
    capped = [ 5 * (2**(attempt - 1)), 3600 ].min
    (capped / 2.0 + rand * (capped / 2.0)).round.seconds
  end

  private

  def resolve(delivery, result)
    attempts = delivery.delivery_attempts.count

    if result.success?
      delivery.update!(status: :succeeded, attempts_count: attempts, next_attempt_at: nil)
    elsif attempts < MAX_ATTEMPTS
      delay = self.class.retry_delay(attempts)
      delivery.update!(status: :failed, attempts_count: attempts, next_attempt_at: delay.from_now)
      DeliveryJob.set(wait: delay).perform_later(delivery)
    else
      delivery.update!(status: :dead, attempts_count: attempts, next_attempt_at: nil)
    end
  end
end
