class CreateCollections < ActiveRecord::Migration[8.1]
  def change
    create_table :collections do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description

      # Default rotation weight for artworks in this collection. An artwork's
      # own weight overrides it.
      t.integer :weight, null: false, default: 1

      # The narrowest aspect ratio worth keeping from this collection. This is
      # per collection because it has to be: 1.30 suits the European canon, but
      # a standard Canadian sketch panel is 8.5x10.5in — 1.235 — and a 1.30
      # floor discards most of a body of work. Knowledge like this belongs in
      # the data, not in a selection script nobody kept.
      t.decimal :minimum_aspect_ratio, precision: 6, scale: 4

      t.timestamps
    end
    add_index :collections, :slug, unique: true
  end
end
