class AddRetryFieldsToDeliveries < ActiveRecord::Migration[8.1]
  def change
    add_column :deliveries, :attempts_count, :integer, null: false, default: 0
    add_column :deliveries, :next_attempt_at, :datetime
  end
end
