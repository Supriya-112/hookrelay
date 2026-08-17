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

  # Takes ownership of this delivery, returning false when someone else already
  # has it or it has finished. The same delivery can reach two workers at once —
  # a scheduled retry can overlap with a sweep, and a queue may hand out a job
  # twice — so the UPDATE decides who POSTs rather than a read-then-write, which
  # would let both of them through and deliver the event twice.
  def claim
    self.class.where(id: id, status: CLAIMABLE_STATUSES)
        .update_all(status: self.class.statuses[:delivering], updated_at: Time.current) == 1
  end
end
