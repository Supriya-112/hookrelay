class EncryptStoredSigningSecrets < ActiveRecord::Migration[8.1]
  # The secrets already in the database were stored as plain text. Writing each one
  # back through the model lands it encrypted — but saving reads the old value
  # first, and reading plain text through an encrypted attribute fails, so the
  # allowance for unencrypted data is switched on for the length of the migration
  # and off again afterwards.
  def up
    with_unencrypted_data_allowed do
      [ Source, Destination ].each do |model|
        model.where.not(signing_secret: nil).find_each do |record|
          # Assigning the same value back wouldn't count as a change and nothing
          # would be written; saying so directly does.
          record.signing_secret_will_change!
          record.save!(validate: false)
        end
      end
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "decrypting the secrets back to plain text would undo the point"
  end

  private

  def with_unencrypted_data_allowed
    was_allowed = ActiveRecord::Encryption.config.support_unencrypted_data
    ActiveRecord::Encryption.config.support_unencrypted_data = true
    yield
  ensure
    ActiveRecord::Encryption.config.support_unencrypted_data = was_allowed
  end
end
