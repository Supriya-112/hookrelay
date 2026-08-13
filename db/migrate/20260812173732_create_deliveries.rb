class CreateDeliveries < ActiveRecord::Migration[8.1]
  def change
    create_table :deliveries do |t|
      t.references :event, null: false, foreign_key: true
      t.references :destination, null: false, foreign_key: true
      t.string :status, null: false, default: "pending"

      t.timestamps
    end
    # One delivery per (event, destination) — a source may fan out to several.
    add_index :deliveries, [ :event_id, :destination_id ], unique: true
  end
end
