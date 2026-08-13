class CreateDeliveryAttempts < ActiveRecord::Migration[8.1]
  def change
    create_table :delivery_attempts do |t|
      t.references :delivery, null: false, foreign_key: true
      t.integer :status_code
      t.text :response_body
      t.integer :duration_ms
      t.string :error

      t.timestamps
    end
  end
end
