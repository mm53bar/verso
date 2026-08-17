class AddMatteInsetToDisplays < ActiveRecord::Migration[8.1]
  # A matte surrounds a picture on all four sides. `resize_and_pad` fits the
  # artwork to the panel, so a picture narrower than the screen touches the top
  # and bottom edges exactly and can only ever produce bars down the sides. That
  # reads as letterboxing, not as a mount board, which is what a screen
  # pretending to be a hanging painting needs.
  #
  # The inset is the minimum margin, as a fraction of the panel's height, so the
  # artwork is scaled down to leave room for it. 0 keeps the old behaviour.
  def change
    add_column :displays, :matte_inset, :decimal, precision: 4, scale: 3,
               default: 0, null: false
  end
end
