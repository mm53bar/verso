class AddFavouriteToArtworks < ActiveRecord::Migration[8.1]
  # A star, and the one thing it does is come up more often.
  #
  # NOT a second weight column. We already deleted one of those: Collection#weight
  # sat unread for a day because Display#weight_for consults the per-screen join
  # instead, and two weights that have to be multiplied make the resulting
  # frequency something you work out rather than read. This is a boolean, and
  # weight_for applies a single named multiplier to it, in the one place weight is
  # decided.
  def change
    add_column :artworks, :favourite, :boolean, default: false, null: false
    add_index :artworks, :favourite
  end
end
