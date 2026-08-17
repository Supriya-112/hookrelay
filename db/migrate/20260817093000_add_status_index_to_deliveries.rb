class AddStatusIndexToDeliveries < ActiveRecord::Migration[8.1]
  # The sweep looks for deliveries by status — overdue retries, claims nobody
  # reported back on — and those are a thin slice of a table that grows with every
  # event. Leading on status keeps all three of its queries off a full scan.
  def change
    add_index :deliveries, [ :status, :next_attempt_at ]
  end
end
