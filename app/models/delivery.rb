class Delivery < ApplicationRecord
  belongs_to :event
  belongs_to :destination
  has_many :delivery_attempts, dependent: :destroy

  # One delivery per (event, destination); the DB has a matching unique index.
  validates :destination_id, uniqueness: { scope: :event_id }

  # pending → (attempt) → succeeded, or failed while retries remain, or dead once
  # the retry budget is exhausted.
  enum :status, { pending: "pending", failed: "failed", succeeded: "succeeded", dead: "dead" }, default: :pending
end
