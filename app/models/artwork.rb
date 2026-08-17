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

  normalizes :title, with: ->(title) { title.squish.presence }

  before_save :derive_aspect_ratio

  scope :active,    -> { where(active: true) }
  scope :reviewed,  -> { where(reviewed: true) }

  # Showable at all, on any screen. Both flags are required: `active` is a
  # curator's switch, `reviewed` means a human has looked at the image.
  scope :eligible,  -> { active.reviewed }

  scope :untitled,  -> { where(title: nil) }
  scope :by_title,  -> { order(Arel.sql("title IS NULL"), :title) }

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
  def rendition_for(display)
    original.variant(**display.variant_transformation)
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
