class CreateApiKeys < ActiveRecord::Migration[8.1]
  def change
    create_table :api_keys do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false
      # Only the digest is kept; see ApiKey.
      t.string :token_digest, null: false
      t.datetime :last_used_at

      t.timestamps
    end
    add_index :api_keys, :token_digest, unique: true
  end
end
