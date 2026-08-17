class AddStorySourceToArtworks < ActiveRecord::Migration[8.1]
  def change
    # Where the story text came from.
    #
    # Kept separate from source_url, which is the provenance of the *image*. A
    # story drawn from Wikipedia is CC BY-SA and has to carry a link back, and a
    # reader deserves to know whether they are reading an encyclopaedia or
    # something written here.
    add_column :artworks, :story_source_url, :string
    add_column :artworks, :story_source_name, :string
  end
end
