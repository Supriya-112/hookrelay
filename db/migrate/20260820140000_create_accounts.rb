class CreateAccounts < ActiveRecord::Migration[8.1]
  def up
    create_table :accounts do |t|
      t.string :name, null: false

      t.timestamps
    end

    add_reference :users, :account, null: false, foreign_key: true
    add_reference :sources, :account, foreign_key: true

    # Sources that predate accounts — a development database, most likely — all
    # move into one account so the column can be required from here on.
    Source.reset_column_information
    if Source.exists?
      account = Account.create!(name: "Default")
      Source.update_all(account_id: account.id)
    end

    change_column_null :sources, :account_id, false
  end

  def down
    remove_reference :sources, :account
    remove_reference :users, :account
    drop_table :accounts
  end
end
