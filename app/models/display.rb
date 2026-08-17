class Display < ApplicationRecord
  include Sluggable

  # How the artwork reaches the screen. A browser polls current.json because it
  # has no other option; a script reads a file because that is easiest. The
  # *decision* is verso's either way — see
  # docs/adr/20260816-verso-owns-the-rotation.md.
  DELIVERIES = %w[ http file ].freeze

  # How an artwork is fitted to the panel. `fill` crops to the panel's shape;
  # `contain` scales the whole picture in and mattes the rest.
  RENDER_MODES = %w[ fill contain ].freeze

  belongs_to :current_artwork, class_name: "Artwork", optional: true
  belongs_to :next_artwork,    class_name: "Artwork", optional: true

  # A screen that mirrors another. The leader picks; followers show the same
  # artwork at their own size and in their own render mode.
  belongs_to :follows_display, class_name: "Display", optional: true
  has_many :followers, class_name: "Display", foreign_key: :follows_display_id,
           inverse_of: :follows_display, dependent: :nullify

  has_many :display_collections, dependent: :destroy
  has_many :collections, through: :display_collections
  has_many :display_overrides, dependent: :destroy
  has_many :display_events, dependent: :destroy

  validates :name, presence: true
  validates :width, :height, :cycle_seconds, numericality: { greater_than: 0 }
  validates :delivery, inclusion: { in: DELIVERIES }
  validates :render_mode, inclusion: { in: RENDER_MODES }
  # A quarter of the height per side would leave half the panel as mount board,
  # which is past a matte and into a joke.
  validates :matte_inset,
            numericality: { greater_than_or_equal_to: 0, less_than: 0.25 }
  validate :cannot_follow_itself
  validates :file_path, presence: true, if: :file_delivery?
  validates :max_crop_fraction,
            numericality: { greater_than_or_equal_to: 0, less_than: 1 }
  validate :file_path_stays_within_delivery_root, if: -> { file_path.present? }

  normalizes :name, with: ->(name) { name.squish }

  scope :active, -> { where(active: true) }

  def to_param = slug

  def http_delivery? = delivery == "http"
  def file_delivery? = delivery == "file"

  def fill? = render_mode == "fill"
  def contain? = render_mode == "contain"

  # A follower shows what its leader shows and keeps the leader's schedule.
  def follower? = follows_display_id.present?

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
  #
  # A follower is never due on its own account: it changes when its leader does,
  # so letting it advance independently is exactly how the two screens would
  # drift apart.
  def due?(now: Time.current)
    return false if follower?

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
    scope = own_eligible_artworks

    # A leader may only pick something every follower can also render — two
    # screens cannot show the same artwork if one of them cannot display it.
    followers.each { |f| scope = scope.where(id: f.own_eligible_artworks.select(:id)) }

    scope
  end

  # What this panel could show if it answered to nobody.
  def own_eligible_artworks
    # Built with query methods rather than a SQL fragment on purpose: the
    # exception lists are usually empty, and `id NOT IN (NULL)` evaluates to
    # unknown rather than true, which silently disqualifies the whole
    # collection. Rails renders an empty `where.not` as a tautology instead.
    suitable = Artwork.eligible.merge(large_enough)
    suitable = suitable.where(aspect_ratio: acceptable_aspect_ratios) if fill?

    from_collections = Artwork
      .where(collection_id: collection_ids)
      .where.not(id: overridden_artwork_ids(false))

    suitable
      .where(id: from_collections)
      .or(suitable.where(id: overridden_artwork_ids(true)))
  end

  # Big enough to render, allowing whatever enlargement its collection permits.
  #
  # Cropping to fill scales by the *larger* of the two ratios, so the source has
  # to beat the panel in both dimensions. Scaling to fit scales by the smaller,
  # so only the limiting dimension has to: a tall picture needs the height, a
  # wide one needs the width. That difference is most of why matting admits so
  # much more of the collection than cropping does.
  #
  # The threshold is per collection, because how much a picture can be enlarged
  # is a fact about the material rather than about the screen — see
  # Collection#max_upscale. One term per distinct allowance, OR'd together, so
  # this stays query methods over one table rather than arithmetic in a SQL
  # string across a join.
  def large_enough
    terms = Collection.pluck(:id, :max_upscale).group_by(&:last).map do |upscale, rows|
      Artwork.where(collection_id: rows.map(&:first)).merge(fits_within(upscale))
    end

    terms.reduce(:or) || Artwork.none
  end

  # Move to the next artwork: record the showing, and line up what follows so
  # the feed can tell a client what to preload.
  #
  # Returns the artwork now showing, or nil when nothing is eligible — an empty
  # collection leaves whatever is on screen alone rather than blanking it.
  def advance!(now: Time.current)
    upcoming = committed_next || pick(now: now)
    return if upcoming.nil?

    transaction do
      display_events.create!(artwork: upcoming, shown_at: now)
      update!(current_artwork: upcoming, current_since: now)
      # Picked after the event is recorded, so the piece just shown has spent a
      # slot and will not immediately be chosen again.
      following = pick(now: now)
      update!(next_artwork: following)

      # Followers do not choose. They are told, so that two screens in two rooms
      # are showing the same picture — which is the whole reason to notice a
      # painting on one and read about it on the other.
      followers.each do |follower|
        follower.display_events.create!(artwork: upcoming, shown_at: now)
        follower.update!(current_artwork: upcoming, next_artwork: following, current_since: now)
      end
    end

    upcoming
  end

  # Weighted, but coverage first. Every eligible artwork spends all of its slots
  # before any of them gets a fresh one, which is what the old shuffle-on-a-timer
  # arrangement could never promise: it re-randomised periodically, so rotation
  # was effectively random *with* replacement and some pieces went unseen for
  # weeks.
  def pick(now: Time.current)
    update!(round_started_at: now) if round_started_at.nil?

    remaining = remaining_slots

    if remaining.empty?
      update!(round_started_at: now)
      remaining = remaining_slots
    end

    # Never show the same piece twice running when there is an alternative. A
    # weighted artwork holds several slots in a round and would otherwise spend
    # two back to back, which on a wall reads as the rotation having stopped.
    alternatives = remaining.except(current_artwork)

    weighted_sample(alternatives.presence || remaining)
  end

  # How this panel wants an artwork transformed.
  #
  # `contain` pads rather than crops, so the whole picture survives and the
  # remainder is matte.
  #
  # With an inset, that is done in two steps rather than one, and the reason is
  # what a matte actually looks like. `resize_and_pad` alone fits the artwork to
  # the panel, so a picture narrower than the screen meets the top and bottom
  # edges exactly and the matte can only appear down the sides. That is
  # letterboxing. Shrinking the artwork into a smaller box first and then
  # centring it on the full panel leaves a margin on all four sides, which is a
  # mount board.
  def variant_transformation
    unless contain?
      return { resize_to_fill: [ width, height ], format: :jpeg, saver: { quality: 88 } }
    end

    return { resize_and_pad: [ width, height, { background: matte_rgb, alpha: false } ],
             format: :jpeg, saver: { quality: 90 } } if matte_inset.to_f.zero?

    { resize_to_limit: matte_inner_size,
      gravity: [ "centre", width, height,
                 { extend: :background, background: matte_rgb } ],
      format: :jpeg, saver: { quality: 90 } }
  end

  # The box the artwork is scaled into, leaving the inset as a margin.
  #
  # Measured off the height on both axes on purpose: an equal *fraction* of each
  # axis would give a wide screen a wider side margin than top margin, and a
  # mount board has an even border.
  def matte_inner_size
    margin = (height * matte_inset.to_f).round

    [ width - margin * 2, height - margin * 2 ]
  end

  # The extension a rendition URL for this display should carry.
  #
  # Derived from the format the variant is actually generated in, so a URL
  # cannot come to disagree with the bytes behind it. `fetch` twice on purpose:
  # a new rendition format that nobody gave an extension to raises here rather
  # than quietly serving `.jpg` over a PNG.
  RENDITION_EXTENSIONS = { jpeg: :jpg, png: :png }.freeze

  def rendition_extension
    RENDITION_EXTENSIONS.fetch(variant_transformation.fetch(:format))
  end

  # "#rrggbb" -> [r, g, b], which is what libvips wants.
  def matte_rgb
    hex = matte_color.to_s.delete_prefix("#")
    return [ 17, 17, 17 ] unless hex.match?(/\A[0-9a-fA-F]{6}\z/)

    hex.scan(/../).map { |pair| pair.to_i(16) }
  end

  # Put the current rendition where a file-delivery consumer will find it.
  #
  # Written to a temporary name in the same directory and renamed into place.
  # rename() within one filesystem is atomic, so a consumer reading on its own
  # unrelated schedule sees either the old image or the new one and never a
  # half-written JPEG. Writing the destination directly is the one way to get
  # file delivery wrong, and the failure would be intermittent and blamed on
  # the consumer.
  def deliver!
    return false unless file_delivery? && current_artwork&.original&.attached?

    destination = absolute_file_path
    destination.dirname.mkpath
    temporary = destination.dirname.join(".#{destination.basename}.#{SecureRandom.hex(4)}")

    begin
      temporary.binwrite(current_artwork.rendition_for(self).processed.download)
      File.rename(temporary, destination)
      true
    ensure
      FileUtils.rm_f(temporary)
    end
  end

  # Generate the rendition for whatever comes next, so a screen never waits on
  # libvips at the moment it swaps.
  #
  # Measured in production: deriving a 1920x1200 crop from a 310MB original took
  # 27 seconds on first request and 1ms once the variant existed. A client
  # preloading next_url warms it incidentally, but relying on that leaves the
  # cliff in place for any client that does not, and for the first artwork after
  # a restart.
  def warm_next_rendition
    return false unless next_artwork&.original&.attached?

    next_artwork.rendition_for(self).processed
    true
  rescue StandardError => e
    Rails.logger.warn("[verso] #{slug}: could not warm next rendition: #{e.class}: #{e.message}")
    false
  end

  # An artwork's own weight scaled by what this screen thinks of its
  # collection. Lets one sub-collection be frequent on one screen and absent
  # from another without duplicating a byte.
  def weight_for(artwork)
    collection_weight = display_collections.find_by(collection_id: artwork.collection_id)&.weight || 1

    artwork.weight * collection_weight
  end

  private
    # Artworks this panel can render when they may be enlarged up to `upscale`.
    #
    # Ceil rather than floor: at 1.0 the two are identical, and above it a
    # rounded-down threshold would admit a piece that lands a pixel short.
    def fits_within(upscale)
      needed_width = (width / upscale).ceil
      needed_height = (height / upscale).ceil

      return Artwork.where(width: needed_width.., height: needed_height..) if fill?

      Artwork
        .where(aspect_ratio: aspect_ratio..).where(width: needed_width..)
        .or(Artwork.where(aspect_ratio: ...aspect_ratio).where(height: needed_height..))
    end

    # The piece lined up last time, provided it is still showable — a curator
    # may have deactivated it, or a re-import may have changed its dimensions,
    # in the meantime.
    def committed_next
      return if next_artwork_id.nil?

      next_artwork if eligible_artworks.exists?(next_artwork_id)
    end

    # artwork => slots left this round. An artwork gets `weight_for` slots and
    # spends one per showing.
    def remaining_slots
      spent = display_events
        .where(shown_at: round_started_at.., artwork_id: eligible_artworks.select(:id))
        .group(:artwork_id)
        .count

      eligible_artworks.each_with_object({}) do |artwork, slots|
        left = weight_for(artwork) - spent.fetch(artwork.id, 0)
        slots[artwork] = left if left.positive?
      end
    end

    # Weighted by slots left rather than uniform, so a piece with three
    # showings due is spread through the round instead of clustering at the end.
    def weighted_sample(slots)
      total = slots.values.sum
      return if total.zero?

      target = rand(total)
      slots.each do |artwork, weight|
        target -= weight
        return artwork if target.negative?
      end

      slots.keys.last
    end

    def cannot_follow_itself
      errors.add(:follows_display, "cannot be itself") if follows_display_id.present? && follows_display_id == id
    end

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
