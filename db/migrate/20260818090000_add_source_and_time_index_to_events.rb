class AddSourceAndTimeIndexToEvents < ActiveRecord::Migration[8.1]
  # The inspector lists a source's events newest first, which is a sort of the
  # whole table behind a source filter without this.
  def change
    add_index :events, [ :source_id, :created_at ]
  end
end
