class CreateEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :events do |t|
      t.references :source, null: false, foreign_key: true
      t.string :http_method, null: false
      t.string :content_type
      t.jsonb :headers, null: false, default: {}
      t.text :body

      t.timestamps
    end
  end
end
