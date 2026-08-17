# Picks up deliveries that no live job will finish. Three ways that happens: a
# worker died between claiming a delivery and recording its outcome, a scheduled
# retry was lost with the queue it sat in, or a fan-out created a delivery whose
# first attempt never got enqueued. Nothing else notices any of them, so without
# this sweep those deliveries sit untouched forever. Runs on a schedule in
# production — see config/recurring.yml.
class SweepStuckDeliveriesJob < ApplicationJob
  queue_as :default

  # How long a claimed delivery may go without reporting an outcome before we
  # assume its worker is gone. Comfortably longer than the client's own timeouts
  # (5s to connect, 10s to read) plus the time to record the attempt.
  CLAIM_TIMEOUT = 5.minutes

  def perform
    recover_abandoned_claims
    # Both of these are safe to enqueue even if the original job does turn up:
    # whichever runs first claims the delivery and the other one returns.
    requeue Delivery.failed.where(next_attempt_at: ..Time.current)
    requeue Delivery.pending.where(created_at: ..CLAIM_TIMEOUT.ago)
  end

  private

  # An abandoned claim is recorded as a failed attempt rather than just released,
  # so it counts against the retry budget — a destination that reliably kills its
  # worker still reaches the dead letter state instead of being swept forever.
  def recover_abandoned_claims
    Delivery.delivering.where(updated_at: ..CLAIM_TIMEOUT.ago).find_each do |delivery|
      result = WebhookClient::Result.new(error: "worker stopped before recording an outcome")
      delay = DeliveryJob.record_outcome(delivery, result)
      DeliveryJob.set(wait: delay).perform_later(delivery) if delay
    end
  end

  def requeue(deliveries)
    deliveries.find_each { |delivery| DeliveryJob.perform_later(delivery) }
  end
end
