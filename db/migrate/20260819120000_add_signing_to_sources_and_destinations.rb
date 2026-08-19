class AddSigningToSourcesAndDestinations < ActiveRecord::Migration[8.1]
  # A source holds the secret its provider was given and the scheme that provider
  # signs with; a destination holds a secret of our own, so what we deliver can be
  # checked at the other end.
  def up
    add_column :sources, :signature_scheme, :string
    add_column :sources, :signing_secret, :string
    add_column :destinations, :signing_secret, :string

    # Destinations created before this generate their secret on create; the ones
    # already here need one, or their deliveries would go out unsigned.
    Destination.reset_column_information
    Destination.where(signing_secret: nil).find_each do |destination|
      destination.update_columns(signing_secret: Destination.generate_unique_secure_token(length: 32))
    end
  end

  def down
    remove_column :sources, :signature_scheme
    remove_column :sources, :signing_secret
    remove_column :destinations, :signing_secret
  end
end
