class CreateDisplays < ActiveRecord::Migration[8.1]
  def change
    create_table :displays do |t|
      t.string :name, null: false
      t.string :slug, null: false

      # Target size. This is what picks the rendition, and it is why one
      # collection can drive two screens with different aspect ratios.
      t.integer :width,  null: false
      t.integer :height, null: false

      # How much of a picture this screen may crop away to fill itself. With a
      # target aspect D, it admits aspect ratios from D*(1-f) to D/(1-f) — at
      # 1.60 and 0.25 that is 1.20 to 2.13, which is close to the range the
      # current collection was hand-filtered to. Suitability is computed from
      # this and the artwork's own dimensions, so it stays correct when a better
      # original is imported.
      t.decimal :max_crop_fraction, precision: 4, scale: 3, null: false, default: 0.25

      # How long one artwork stays up. Per screen, because it has to be.
      t.integer :cycle_seconds, null: false

      # How the artwork reaches this screen. "http" means the client polls
      # current.json; "file" means verso writes the rendition to file_path and
      # something else picks it up. Same decision, two transports.
      t.string :delivery, null: false, default: "http"
      t.string :file_path

      # The cursor. Nullable because a display has shown nothing until the
      # rotation job first runs.
      t.references :current_artwork, null: true, foreign_key: { to_table: :artworks }
      t.references :next_artwork,    null: true, foreign_key: { to_table: :artworks }
      t.datetime :current_since

      t.boolean :active, null: false, default: true

      t.timestamps
    end
    add_index :displays, :slug, unique: true
  end
end
