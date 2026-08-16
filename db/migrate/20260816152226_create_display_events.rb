class CreateDisplayEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :display_events do |t|
      t.references :display, null: false, foreign_key: true
      t.references :artwork, null: false, foreign_key: true
      t.datetime :shown_at, null: false

      t.timestamps
    end

    # "What was on that screen last Tuesday", and eventually "nothing repeated
    # from the last N".
    add_index :display_events, [ :display_id, :shown_at ]
  end
end
