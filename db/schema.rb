# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_17_170215) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "artists", force: :cascade do |t|
    t.text "bio"
    t.integer "birth_year"
    t.datetime "created_at", null: false
    t.integer "death_year"
    t.string "name", null: false
    t.string "nationality"
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_artists_on_slug", unique: true
  end

  create_table "artworks", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.integer "artist_id"
    t.decimal "aspect_ratio", precision: 6, scale: 4
    t.text "blurb"
    t.integer "collection_id", null: false
    t.datetime "created_at", null: false
    t.string "credit_line"
    t.string "current_location"
    t.integer "height"
    t.string "license"
    t.string "medium"
    t.boolean "reviewed", default: false, null: false
    t.string "slug", null: false
    t.string "source"
    t.string "source_file"
    t.string "source_url"
    t.text "story"
    t.string "story_source_name"
    t.string "story_source_url"
    t.string "title"
    t.datetime "updated_at", null: false
    t.integer "weight", default: 1, null: false
    t.integer "width"
    t.string "wikidata_qid"
    t.string "year_text"
    t.index ["artist_id"], name: "index_artworks_on_artist_id"
    t.index ["collection_id", "active", "reviewed", "aspect_ratio"], name: "index_artworks_on_eligibility"
    t.index ["collection_id"], name: "index_artworks_on_collection_id"
    t.index ["slug"], name: "index_artworks_on_slug", unique: true
  end

  create_table "collections", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.decimal "max_upscale", precision: 4, scale: 2, default: "1.0", null: false
    t.decimal "minimum_aspect_ratio", precision: 6, scale: 4
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_collections_on_slug", unique: true
  end

  create_table "display_collections", force: :cascade do |t|
    t.integer "collection_id", null: false
    t.datetime "created_at", null: false
    t.integer "display_id", null: false
    t.datetime "updated_at", null: false
    t.integer "weight", default: 1, null: false
    t.index ["collection_id"], name: "index_display_collections_on_collection_id"
    t.index ["display_id", "collection_id"], name: "index_display_collections_on_display_id_and_collection_id", unique: true
    t.index ["display_id"], name: "index_display_collections_on_display_id"
  end

  create_table "display_events", force: :cascade do |t|
    t.integer "artwork_id", null: false
    t.datetime "created_at", null: false
    t.integer "display_id", null: false
    t.datetime "shown_at", null: false
    t.datetime "updated_at", null: false
    t.index ["artwork_id"], name: "index_display_events_on_artwork_id"
    t.index ["display_id", "shown_at"], name: "index_display_events_on_display_id_and_shown_at"
    t.index ["display_id"], name: "index_display_events_on_display_id"
  end

  create_table "display_overrides", force: :cascade do |t|
    t.boolean "allowed", null: false
    t.integer "artwork_id", null: false
    t.datetime "created_at", null: false
    t.integer "display_id", null: false
    t.datetime "updated_at", null: false
    t.index ["artwork_id"], name: "index_display_overrides_on_artwork_id"
    t.index ["display_id", "artwork_id"], name: "index_display_overrides_on_display_id_and_artwork_id", unique: true
    t.index ["display_id"], name: "index_display_overrides_on_display_id"
  end

  create_table "displays", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.integer "current_artwork_id"
    t.datetime "current_since"
    t.integer "cycle_seconds", null: false
    t.string "delivery", default: "http", null: false
    t.string "file_path"
    t.integer "follows_display_id"
    t.integer "height", null: false
    t.string "matte_color", default: "#111111", null: false
    t.decimal "max_crop_fraction", precision: 4, scale: 3, default: "0.25", null: false
    t.string "name", null: false
    t.integer "next_artwork_id"
    t.string "render_mode", default: "fill", null: false
    t.datetime "round_started_at"
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.integer "width", null: false
    t.index ["current_artwork_id"], name: "index_displays_on_current_artwork_id"
    t.index ["follows_display_id"], name: "index_displays_on_follows_display_id"
    t.index ["next_artwork_id"], name: "index_displays_on_next_artwork_id"
    t.index ["slug"], name: "index_displays_on_slug", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "artworks", "artists"
  add_foreign_key "artworks", "collections"
  add_foreign_key "display_collections", "collections"
  add_foreign_key "display_collections", "displays"
  add_foreign_key "display_events", "artworks"
  add_foreign_key "display_events", "displays"
  add_foreign_key "display_overrides", "artworks"
  add_foreign_key "display_overrides", "displays"
  add_foreign_key "displays", "artworks", column: "current_artwork_id"
  add_foreign_key "displays", "artworks", column: "next_artwork_id"
  add_foreign_key "displays", "displays", column: "follows_display_id"
end
