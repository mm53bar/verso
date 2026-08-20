# A screen that changes on the wall clock rather than on a stopwatch.
#
# `cycle_seconds` measures from the last change, so a daily interval lands
# wherever the previous one happened to finish and drifts by up to a tick every
# day. A television is watched at particular hours, so *when* it changes is the
# whole requirement, and an interval cannot express it.
#
# Nullable, and null keeps the interval behaviour, which is what every screen had
# before this column existed.
class AddRotateAtToDisplays < ActiveRecord::Migration[8.1]
  def change
    add_column :displays, :rotate_at, :string
  end
end
