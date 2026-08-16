class Collection < ApplicationRecord
  include Sluggable

  # Restrict rather than cascade: deleting a collection should not be a way to
  # silently delete a hundred artworks and their stored originals.
  has_many :artworks, dependent: :restrict_with_error

  has_many :display_collections, dependent: :destroy
  has_many :displays, through: :display_collections

  validates :name, presence: true
  validates :weight, numericality: { greater_than: 0 }
  validates :minimum_aspect_ratio,
            numericality: { greater_than: 0 }, allow_nil: true

  normalizes :name, with: ->(name) { name.squish }

  scope :by_name, -> { order(:name) }

  def to_param = slug
end
