class CreateDestinations < ActiveRecord::Migration[8.1]
  def change
    create_table :destinations do |t|
      t.references :source, null: false, foreign_key: true
      t.string :url, null: false
      t.string :name

      t.timestamps
    end
  end
end
