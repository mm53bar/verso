# A per-artwork exception to what a screen's collections would otherwise admit.
# `allowed: true` forces one piece onto a screen that excludes its collection;
# `allowed: false` keeps one off a screen that would otherwise carry it. No row
# means "no opinion, follow the collection".
class DisplayOverride < ApplicationRecord
  belongs_to :display
  belongs_to :artwork

  validates :artwork_id, uniqueness: { scope: :display_id }
end
