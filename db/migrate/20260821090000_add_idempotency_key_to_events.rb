class AddIdempotencyKeyToEvents < ActiveRecord::Migration[8.1]
  # What the provider called this delivery, when it told us. Unique per source, so
  # a retry of the same webhook can't become a second event — and NULLs don't
  # collide in Postgres, so sources whose provider says nothing are unaffected.
  def change
    add_column :events, :idempotency_key, :string
    add_index :events, [ :source_id, :idempotency_key ], unique: true
  end
end
