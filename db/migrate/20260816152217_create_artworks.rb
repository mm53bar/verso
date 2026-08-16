class CreateArtworks < ActiveRecord::Migration[8.1]
  def change
    create_table :artworks do |t|
      # Nullable. Some pieces arrive with no known title and may never get one —
      # a guessed title is worse than an absent one, because it reads as fact.
      t.string :title
      t.string :slug, null: false
      t.string :year_text          # free text: "c. 1917", "1920-21"

      # Two story fields, deliberately. `blurb` is one or two sentences and is
      # what gets spoken aloud, so it stays plain: no emoji, no typographic
      # dashes. `story` is long form for a screen. One field cannot serve both —
      # a paragraph of interpretation is unbearable read aloud, and a single
      # spoken sentence is thin on a panel.
      t.text :blurb
      t.text :story

      t.string :medium
      t.string :current_location   # the museum or collection holding it now

      # Provenance.
      t.string :source
      t.string :source_url
      t.string :source_file
      t.string :wikidata_qid
      t.string :license
      t.string :credit_line

      # Rotation. `active` is a curator's switch; `reviewed` is whether a human
      # has actually looked at this image. They are not the same thing, and the
      # feed requires both: an automatic ingest path must not be able to put
      # something unseen on a wall. A title blocklist has already proven
      # insufficient for content filtering, so the default is false.
      t.boolean :active,   null: false, default: true
      t.boolean :reviewed, null: false, default: false
      t.integer :weight,   null: false, default: 1

      # Dimensions of the stored original, recorded at import. Whether a piece
      # suits a given screen is derived from these against that display's target
      # size, never hand-flagged per device — a hand-maintained flag would drift
      # the moment a better original is imported.
      t.integer :width
      t.integer :height
      t.decimal :aspect_ratio, precision: 6, scale: 4

      # Optional: some pieces have no known artist, and the cartoon wallpapers
      # never will.
      t.references :artist, null: true, foreign_key: true
      t.references :collection, null: false, foreign_key: true

      t.timestamps
    end

    add_index :artworks, :slug, unique: true

    # The feed's hot path: eligible artworks in a collection this display
    # carries, narrow enough for its aspect ratio.
    add_index :artworks, [ :collection_id, :active, :reviewed, :aspect_ratio ],
              name: "index_artworks_on_eligibility"
  end
end
