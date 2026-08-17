class ChangeEventBodyToBinary < ActiveRecord::Migration[8.1]
  # Providers send gzip, protobuf and other payloads that aren't valid UTF-8, and
  # a text column makes Postgres reject those bytes outright — the request 500s
  # and the event is lost. bytea keeps whatever arrived, byte for byte.
  def up
    change_column :events, :body, :binary, using: "convert_to(body, 'UTF8')"
  end

  def down
    change_column :events, :body, :text, using: "convert_from(body, 'UTF8')"
  end
end
