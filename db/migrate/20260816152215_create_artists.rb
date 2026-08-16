class CreateArtists < ActiveRecord::Migration[8.1]
  def change
    create_table :artists do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.integer :birth_year
      t.integer :death_year
      t.string :nationality
      t.text :bio

      t.timestamps
    end
    add_index :artists, :slug, unique: true
  end
end
