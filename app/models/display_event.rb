# One artwork's turn on one screen. Recorded by the rotation job, which makes
# history a side effect of owning the rotation rather than a feature anyone had
# to build.
class DisplayEvent < ApplicationRecord
  belongs_to :display
  belongs_to :artwork

  validates :shown_at, presence: true

  scope :recent, -> { order(shown_at: :desc) }
end
