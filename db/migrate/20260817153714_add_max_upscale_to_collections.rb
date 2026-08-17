class AddMaxUpscaleToCollections < ActiveRecord::Migration[8.1]
  # How far a piece from this collection may be enlarged to fill a screen.
  #
  # 1.0 -- never enlarge -- is the rule the whole collection ran under until now,
  # and stays the default and the right answer for painting. Cartoons are the
  # exception: cel and watercolour art is flat colour bounded by line, so there
  # is little pixel-level detail for interpolation to invent, and 2x is close to
  # invisible at the distance a television is watched from. Enlarging a
  # photograph of an oil painting the same way looks like exactly what it is.
  def change
    add_column :collections, :max_upscale, :decimal,
               precision: 4, scale: 2, default: 1.0, null: false
  end
end
