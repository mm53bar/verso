class Artwork < ApplicationRecord
  include Sluggable

  belongs_to :artist, optional: true
  belongs_to :collection

  has_many :display_events, dependent: :destroy
  has_many :display_overrides, dependent: :destroy

  # The original at full resolution. Every display-sized image is derived from
  # it — see docs/adr/20260816-active-storage-with-round-trippable-export.md.
  # There are no named variants because display sizes are rows, not constants.
  has_one_attached :original

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

  # A JPEG cropped to fill this display exactly. Generated on demand and cached
  # by Active Storage; the URL a client sees must not embed the variant key, or
  # regenerating it would make a screen swap for no reason.
  def rendition_for(display)
    original.variant(
      resize_to_fill: [ display.width, display.height ],
      format: :jpeg,
      saver: { quality: 88 }
    )
  end

  # True when this piece can fill the display without being upscaled. Cropping
  # to fill scales by max(target_w/w, target_h/h), so covering the target
  # without enlarging means being at least as large in both dimensions.
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
