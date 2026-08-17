class Collection < ApplicationRecord
  include Sluggable

  # Restrict rather than cascade: deleting a collection should not be a way to
  # silently delete a hundred artworks and their stored originals.
  has_many :artworks, dependent: :restrict_with_error

  has_many :display_collections, dependent: :destroy
  has_many :displays, through: :display_collections

  validates :name, presence: true
  validates :weight, numericality: { greater_than: 0 }
  # Note the difference between these two, because the names invite confusion:
  # minimum_aspect_ratio records how this collection was *sourced* and nothing
  # reads it at display time, while max_upscale is consulted on every rotation —
  # Display#large_enough divides its panel by it.
  validates :minimum_aspect_ratio,
            numericality: { greater_than: 0 }, allow_nil: true
  # Below 1 would demand a piece be larger than the panel, which is not a floor
  # anyone wants; the ceiling is where enlargement stops being defensible even
  # for flat art.
  validates :max_upscale, numericality: { greater_than_or_equal_to: 1, less_than_or_equal_to: 4 }

  normalizes :name, with: ->(name) { name.squish }

  scope :by_name, -> { order(:name) }

  def to_param = slug
end
