class Collection < ApplicationRecord
  include Sluggable

  # Restrict rather than cascade: deleting a collection should not be a way to
  # silently delete a hundred artworks and their stored originals.
  has_many :artworks, dependent: :restrict_with_error

  has_many :display_collections, dependent: :destroy
  has_many :displays, through: :display_collections

  validates :name, presence: true
  # These two look alike and are not. max_upscale is consulted on every rotation
  # — Display#large_enough divides its panel by it. minimum_aspect_ratio is
  # *provenance*: it records the floor a collection was sourced against, which is
  # why the Canadian collection holds 1.235 sketch panels where the European one
  # is floored at 1.30. Nothing enforces it, deliberately — suitability is
  # computed per display, and a second aspect gate here would refuse pieces a
  # screen could happily show.
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
