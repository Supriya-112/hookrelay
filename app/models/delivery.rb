class Delivery < ApplicationRecord
  belongs_to :event
  belongs_to :destination
  has_many :delivery_attempts, dependent: :destroy

  # One delivery per (event, destination); the DB has a matching unique index.
  validates :destination_id, uniqueness: { scope: :event_id }

  # pending → delivering → succeeded, or back to failed while retries remain, or
  # dead once the retry budget is exhausted.
  enum :status, {
    pending: "pending", delivering: "delivering", failed: "failed",
    succeeded: "succeeded", dead: "dead"
  }, default: :pending

  # States a worker may pick up: never attempted, or waiting on a retry.
  CLAIMABLE_STATUSES = %w[pending failed].freeze

  # States that won't change again on their own: a retry budget exhausted or an
  # attempt that landed.
  CONCLUDED_STATUSES = %w[succeeded dead].freeze

  # Keep an open event page current as deliveries are created and resolve. `claim`
  # deliberately isn't broadcast: it writes with update_all, so the momentary
  # delivering state doesn't reach the page — the row updates when the attempt
  # lands, which is what a reader cares about.
  after_create_commit -> { broadcast_append_later_to event, target: "deliveries", partial: "deliveries/delivery", locals: { delivery: self } }
  after_update_commit -> { broadcast_replace_later_to event, target: row_dom_id, partial: "deliveries/delivery", locals: { delivery: self } }

  # Takes ownership of this delivery, returning false when someone else already
  # has it or it has finished. The same delivery can reach two workers at once —
  # a scheduled retry can overlap with a sweep, and a queue may hand out a job
  # twice — so the UPDATE decides who POSTs rather than a read-then-write, which
  # would let both of them through and deliver the event twice.
  def claim
    self.class.where(id: id, status: CLAIMABLE_STATUSES)
        .update_all(status: self.class.statuses[:delivering], updated_at: Time.current) == 1
  end

  # Sends this delivery again from the top: a fresh retry budget, queued straight
  # away. Returns false for a delivery a worker is already holding — it is on its
  # way, and resetting it would race whoever has it.
  def replay
    return false if delivering?

    reset_for_replay!
    DeliveryJob.perform_later(self)
    true
  end

  # Clears the outcome of the last run without touching its attempts, which stay
  # as the record of what happened. Event#replay uses this to reset a whole event
  # before one fan-out queues the work.
  def reset_for_replay!
    update!(status: :pending, attempts_count: 0, next_attempt_at: nil, replayed_at: Time.current)
  end

  def replayed?
    replayed_at.present?
  end

  # The elements the inspector renders for this delivery. Broadcasts have to name
  # the same ids the page did, so both come from here.
  def row_dom_id
    "delivery_#{id}"
  end

  def attempts_dom_id
    "delivery_#{id}_attempts"
  end
end
