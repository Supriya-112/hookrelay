class Delivery < ApplicationRecord
  belongs_to :event
  belongs_to :destination
  has_many :delivery_attempts, dependent: :destroy

  # One delivery per (event, destination); the DB has a matching unique index.
  validates :destination_id, uniqueness: { scope: :event_id }

  # pending until an attempt resolves it; retries and dead-lettering arrive in M3.
  enum :status, { pending: "pending", succeeded: "succeeded", failed: "failed" }, default: :pending
end
