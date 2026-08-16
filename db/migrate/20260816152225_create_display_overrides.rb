class CreateDisplayOverrides < ActiveRecord::Migration[8.1]
  def change
    create_table :display_overrides do |t|
      t.references :display, null: false, foreign_key: true
      t.references :artwork, null: false, foreign_key: true

      # The exception to the collection rule, in both directions: true forces a
      # single piece onto a screen whose collections exclude it, false keeps one
      # off a screen that would otherwise carry it. Absence means "no opinion,
      # follow the collection".
      t.boolean :allowed, null: false

      t.timestamps
    end

    add_index :display_overrides, [ :display_id, :artwork_id ], unique: true
  end
end
