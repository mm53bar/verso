class RemoveWeightFromCollections < ActiveRecord::Migration[8.1]
  # There were two weights and only one of them did anything.
  #
  # Display#weight_for multiplies an artwork's own weight by the weight on
  # `display_collections`, and never read this column. It was seeded to 3 for
  # Cartoons specifically to stop a small collection being diluted by a large
  # one, and for a day that had no effect whatsoever, silently.
  #
  # The per-screen weight is the one to keep: the whole point of that join is
  # that a collection can be frequent on one screen and absent from another, and
  # a global weight fights it. Two weights would have to be multiplied together,
  # and then the resulting frequency is something you work out rather than read.
  def up
    remove_column :collections, :weight
  end

  def down
    add_column :collections, :weight, :integer, null: false, default: 1
  end
end
