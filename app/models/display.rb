class Display < ApplicationRecord
  include Sluggable

  # How the artwork reaches the screen. A browser polls current.json because it
  # has no other option; a script reads a file because that is easiest. The
  # *decision* is verso's either way — see
  # docs/adr/20260816-verso-owns-the-rotation.md.
  DELIVERIES = %w[ http file ].freeze

  belongs_to :current_artwork, class_name: "Artwork", optional: true
  belongs_to :next_artwork,    class_name: "Artwork", optional: true

  has_many :display_collections, dependent: :destroy
  has_many :collections, through: :display_collections
  has_many :display_overrides, dependent: :destroy
  has_many :display_events, dependent: :destroy

  validates :name, presence: true
  validates :width, :height, :cycle_seconds, numericality: { greater_than: 0 }
  validates :delivery, inclusion: { in: DELIVERIES }
  validates :file_path, presence: true, if: :file_delivery?
  validates :max_crop_fraction,
            numericality: { greater_than_or_equal_to: 0, less_than: 1 }
  validate :file_path_stays_within_delivery_root, if: -> { file_path.present? }

  normalizes :name, with: ->(name) { name.squish }

  scope :active, -> { where(active: true) }

  def to_param = slug

  def http_delivery? = delivery == "http"
  def file_delivery? = delivery == "file"

  # Where the rotation job actually writes. `file_path` is stored relative to
  # the configured delivery root so that an operator can put the directory
  # wherever their disk is laid out, and so that a row in an unauthenticated
  # app cannot name a file outside it.
  def absolute_file_path
    return if file_path.blank?

    Verso.delivery_root.join(file_path).expand_path
  end

  def aspect_ratio = (width.to_d / height).round(4)

  # Nothing has been shown yet, or the current piece has had its turn.
  def due?(now: Time.current)
    current_since.nil? || current_since + cycle_seconds <= now
  end

  # Aspect ratios this screen will accept, derived from its own shape and how
  # much it is willing to crop. Cropping a ratio A to fill a screen of ratio D
  # discards (A-D)/A when A is wider and (D-A)/D when it is narrower; holding
  # both under f gives D*(1-f) .. D/(1-f).
  def acceptable_aspect_ratios
    slack = 1 - max_crop_fraction
    (aspect_ratio * slack)..(aspect_ratio / slack)
  end

  # Everything this screen is allowed to show, right now.
  #
  # Three independent facts compose here, and they deliberately live in three
  # different places: whether the piece is showable at all (its own flags),
  # whether it belongs on *this* screen (collections, plus per-artwork
  # exceptions), and whether it physically suits the panel (computed from the
  # stored original's dimensions, never hand-flagged).
  #
  # An override bypasses collection membership only. It cannot force an
  # unreviewed piece or one too small for the panel onto a wall.
  def eligible_artworks
    # Built with query methods rather than a SQL fragment on purpose: the
    # exception lists are usually empty, and `id NOT IN (NULL)` evaluates to
    # unknown rather than true, which silently disqualifies the whole
    # collection. Rails renders an empty `where.not` as a tautology instead.
    suitable = Artwork
      .eligible
      .where(width: width.., height: height..)
      .where(aspect_ratio: acceptable_aspect_ratios)

    from_collections = Artwork
      .where(collection_id: collection_ids)
      .where.not(id: overridden_artwork_ids(false))

    suitable
      .where(id: from_collections)
      .or(suitable.where(id: overridden_artwork_ids(true)))
  end

  # An artwork's own weight scaled by what this screen thinks of its
  # collection. Lets one sub-collection be frequent on one screen and absent
  # from another without duplicating a byte.
  def weight_for(artwork)
    collection_weight = display_collections.find_by(collection_id: artwork.collection_id)&.weight || 1

    artwork.weight * collection_weight
  end

  private
    def overridden_artwork_ids(allowed)
      display_overrides.where(allowed: allowed).pluck(:artwork_id)
    end

    # Pathname#join replaces the root outright when given an absolute path, and
    # expand_path resolves any "..", so both escape attempts land outside the
    # root and are caught by the same comparison.
    def file_path_stays_within_delivery_root
      root = Verso.delivery_root.expand_path

      unless absolute_file_path.to_s.start_with?("#{root}#{File::SEPARATOR}")
        errors.add(:file_path, "must stay inside the configured delivery directory")
      end
    end
end
