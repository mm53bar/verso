class CreateDisplayCollections < ActiveRecord::Migration[8.1]
  def change
    create_table :display_collections do |t|
      t.references :display, null: false, foreign_key: true
      t.references :collection, null: false, foreign_key: true

      # Weight for this collection *on this screen*. Cartoons can be frequent in
      # the kitchen and absent from the living room without duplicating a single
      # byte — which is the thing a per-device directory could never express.
      t.integer :weight, null: false, default: 1

      t.timestamps
    end

    add_index :display_collections, [ :display_id, :collection_id ], unique: true
  end
end
