class Artist < ApplicationRecord
  include Sluggable

  # Nullify rather than destroy: an artwork whose artist record goes away is
  # still an artwork, and that is exactly the state most of the collection
  # starts in.
  has_many :artworks, dependent: :nullify

  validates :name, presence: true

  normalizes :name, with: ->(name) { name.squish }

  scope :by_name, -> { order(:name) }

  def to_param = slug

  def lifespan
    return if birth_year.blank?

    "#{birth_year}–#{death_year}"
  end
end
