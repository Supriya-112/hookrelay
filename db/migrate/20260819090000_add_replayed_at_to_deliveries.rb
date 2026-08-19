class AddReplayedAtToDeliveries < ActiveRecord::Migration[8.1]
  # When a delivery was last sent again by hand. Attempts from before it stay on
  # the record, so this is what separates "tried five times and died" from "tried
  # five times, then someone replayed it".
  def change
    add_column :deliveries, :replayed_at, :datetime
  end
end
