class Artwork < ApplicationRecord
  include Sluggable

  belongs_to :artist, optional: true
  belongs_to :collection

  has_many :display_events, dependent: :destroy
  has_many :display_overrides, dependent: :destroy

  # The original at full resolution. Every display-sized image is derived from
  # it — see docs/adr/20260816-active-storage-with-round-trippable-export.md.
  #
  # The browse thumbnail is a named variant with `preprocessed: true`, so Active
  # Storage generates it in the background when the original is attached rather
  # than when someone first loads the page. Variants are lazy by default, which
  # is fine for small originals and not fine for these: measured on the NAS, a
  # cold 480x300 from a 717MB source takes 42 seconds against 32ms once cached,
  # and Puma has three threads to lose to it.
  #
  # Display renditions cannot be named variants — their sizes come from Display
  # rows at runtime, and named variants have to be declared statically. Those
  # are pre-generated explicitly instead; see #warm_derivatives!.
  # EVERY size the app displays is named here, and nowhere else.
  #
  # An inline `variant(resize_to_limit: ...)` in a view is a variant nothing
  # warms, because the warmer cannot know about it. That is not hypothetical:
  # naming only the thumbnail left the artwork detail page deriving a 1400px
  # image from a 23MB original on demand, which is tens of seconds on the NAS.
  # If a view needs a new size, it gets a name here.
  has_one_attached :original do |attachable|
    attachable.variant :thumb,  resize_to_fill: [ 480, 300 ], format: :jpeg,
                       saver: { quality: 80 }, preprocessed: true
    attachable.variant :tile,   resize_to_fill: [ 160, 100 ], format: :jpeg,
                       saver: { quality: 80 }, preprocessed: true
    attachable.variant :detail, resize_to_limit: [ 1400, 1400 ], format: :jpeg,
                       saver: { quality: 85 }, preprocessed: true
  end

  validates :weight, numericality: { greater_than: 0 }

  # Named for the picture rather than for libvips. Its `crop:` option says "keep
  # the low edge" or "keep the high edge" of whichever axis is being cropped,
  # which is correct and unreadable: `low` is the top when the crop is vertical
  # and the left when it is horizontal. Storing top/bottom and left/right keeps
  # the intent legible in the database, and CROP_EDGES translates in one place.
  CROP_FOCUS_X = %w[ left centre right ].freeze
  CROP_FOCUS_Y = %w[ top centre bottom ].freeze
  CROP_EDGES = { "left" => :low, "top" => :low, "right" => :high, "bottom" => :high }.freeze

  validates :crop_focus_x, inclusion: { in: CROP_FOCUS_X }, allow_nil: true
  # Same ceiling as a Display's: past a quarter of the picture the crop is the
  # subject. Deliberately allowed higher here, because the point of the column is
  # that a particular picture is worth more than the general rule.
  validates :max_crop_fraction,
            numericality: { greater_than_or_equal_to: 0, less_than: 1 }, allow_nil: true
  validates :crop_focus_y, inclusion: { in: CROP_FOCUS_Y }, allow_nil: true

  normalizes :title, with: ->(title) { title.squish.presence }

  before_save :derive_aspect_ratio

  scope :active,    -> { where(active: true) }
  scope :reviewed,  -> { where(reviewed: true) }

  # Showable at all, on any screen. Both flags are required: `active` is a
  # curator's switch, `reviewed` means a human has looked at the image.
  scope :eligible,  -> { active.reviewed }

  scope :untitled,  -> { where(title: nil) }
  scope :starred,   -> { where(favourite: true) }
  scope :by_title,  -> { order(Arel.sql("title IS NULL"), :title) }

  # Search runs in SQL rather than in the browser, because the browse index is
  # paged at 48 and filtering the rendered page would silently hide matches on
  # every other page. LIKE over a few hundred rows on SQLite is faster than the
  # round trip it saves, and the query ends up in the URL, so a search survives a
  # refresh and the back button.
  scope :matching, ->(query) {
    term = "%#{query.to_s.strip.downcase.gsub(/[%_]/) { |c| "\\#{c}" }}%"
    next all if query.to_s.strip.blank?

    left_joins(:artist, :collection)
      .where(
        "LOWER(artworks.title) LIKE :t OR LOWER(artworks.year_text) LIKE :t OR " \
        "LOWER(artworks.medium) LIKE :t OR LOWER(artworks.current_location) LIKE :t OR " \
        "LOWER(artworks.blurb) LIKE :t OR LOWER(artists.name) LIKE :t OR " \
        "LOWER(collections.name) LIKE :t OR LOWER(artworks.source) LIKE :t",
        t: term
      )
      .distinct
  }

  def to_param = slug

  def display_title
    title.presence || "Untitled"
  end

  def thumbnail = original.variant(:thumb)
  def tile       = original.variant(:tile)
  def detail     = original.variant(:detail)

  # Generate what Active Storage will not generate for us.
  #
  # The named thumbnail looks after itself on attach. Display renditions are
  # sized from Display rows, so they cannot be declared as named variants and
  # have to be asked for. This also backfills artworks attached before the
  # thumbnail became preprocessed.
  def warm_derivatives!
    return 0 unless original.attached?

    [ thumbnail, tile, detail ].each(&:processed)
    Display.active.each { |display| rendition_for(display).processed }
    3 + Display.active.count
  end

  # A JPEG fitted to this display — cropped to fill, or scaled and matted,
  # depending on what that screen is for. Generated on demand and cached by
  # Active Storage; the URL a client sees must not embed the variant key, or
  # regenerating it would make a screen swap for no reason.
  # The display decides the shape; the artwork decides which part of itself to
  # give up to reach it. See #crop_option.
  def rendition_for(display)
    original.variant(**display.variant_transformation(crop: crop_edge_for(display)))
  end

  # A short fingerprint of the BYTES a display's rendition will have.
  #
  # WHY THIS EXISTS. A rendition URL names an artwork and a display and nothing
  # else, deliberately, so that a screen is not made to re-fetch every time a
  # variant is regenerated. That was sound while the bytes were a function of
  # (artwork, display) — and #crop_edge_for made them a function of (artwork,
  # display, crop focus). The invariant broke quietly and cost twenty minutes of a
  # television showing an old crop: Home Assistant skips an upload when the
  # artwork id matches what it last sent, and the rendition URL is served
  # `immutable` with a year of max-age, so nothing between here and the glass had
  # any reason to look again.
  #
  # Computed from the original's storage key and the transformation's own digest,
  # which together are exactly what determines the output. Deliberately NOT the
  # variant's checksum: that would mean generating the variant to name it, and
  # this is called on every feed request, three clients polling every 60 seconds.
  # Nothing here touches the disk.
  def rendition_fingerprint(display)
    return unless original.attached?

    variation = rendition_for(display).variation

    Digest::SHA256.hexdigest("#{original.blob.key}/#{variation.digest}")[0, 8]
  end

  # Which edge of this artwork to keep when this display crops it, as a libvips
  # value, or nil for the default centred crop.
  #
  # NIL RATHER THAN :centre, and that is not a style choice. The transformation
  # hash *is* the Active Storage variant key, so spelling out the default would
  # change the key of every rendition in the collection and regenerate all of them
  # to produce byte-identical images. Returning nil means this feature cannot
  # alter a single artwork that has not opted in.
  #
  # Which axis matters is computed, not stored. Cropping to fill only ever
  # discards from the axis the artwork has too much of, so a piece wider than the
  # panel loses its sides and a taller one loses its top and bottom — and exactly
  # one of the two stored preferences can ever apply.
  def crop_edge_for(display)
    return unless display.fill?
    return if aspect_ratio.blank?

    focus = aspect_ratio > display.aspect_ratio ? crop_focus_x : crop_focus_y

    CROP_EDGES[focus]
  end

  # True when this piece can *fill* the display without being upscaled. Cropping
  # to fill scales by max(target_w/w, target_h/h), so covering the target
  # without enlarging means being at least as large in both dimensions. A
  # matting display has a laxer test — see Display#large_enough.
  def fills?(display)
    return false if width.blank? || height.blank?

    width >= display.width && height >= display.height
  end

  # Read the stored original's real dimensions. Active Storage analyses images
  # on attach, but not synchronously, so the importer calls this once the
  # analysis has run.
  def record_dimensions!
    return unless original.attached?

    original.analyze unless original.analyzed?
    metadata = original.metadata

    update!(width: metadata["width"], height: metadata["height"])
  end

  private
    def slug_source
      [ artist&.name, title ].compact_blank.join(" ").presence ||
        File.basename(source_file.to_s, ".*").presence
    end

    def derive_aspect_ratio
      self.aspect_ratio = if width.to_i.positive? && height.to_i.positive?
        (width.to_d / height).round(4)
      end
    end
end
