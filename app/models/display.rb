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

  # Offered by the settings screen. Deliberately not a validation — any positive
  # number of seconds is a legal interval, and a row already holding an odd one
  # keeps it. These are the ones anyone actually asks for.
  CYCLE_CHOICES = [ 5.minutes, 15.minutes, 30.minutes, 1.hour, 2.hours, 4.hours,
                    6.hours, 12.hours, 1.day ].map(&:to_i).freeze

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
  # A time of day, 24-hour, in the app's zone. Null means the screen runs on
  # cycle_seconds instead, which is what every screen did before this existed.
  validates :rotate_at, format: { with: /\A([01]\d|2[0-3]):[0-5]\d\z/,
                                  message: "must be a time of day like 03:00" },
            allow_nil: true

  normalizes :name, with: ->(name) { name.squish }
  # An <input type="time"> submits "03:00" or "03:00:00" depending on the
  # browser, and a person typing it leaves off the leading zero. All three name
  # the same minute. Anything that is not a time is left alone rather than
  # coerced, so the validation above rejects it instead of it becoming midnight.
  normalizes :rotate_at, with: ->(value) {
    match = value.to_s.strip.match(/\A(\d{1,2}):(\d{2})(?::\d{2})?\z/)
    match ? format("%02d:%02d", match[1].to_i, match[2].to_i) : value.presence
  }

  scope :active, -> { where(active: true) }

  def to_param = slug

  def http_delivery? = delivery == "http"
  def file_delivery? = delivery == "file"

  def fill? = render_mode == "fill"
  def contain? = render_mode == "contain"

  # A follower shows what its leader shows and keeps the leader's schedule.
  def follower? = follows_display_id.present?

  # This screen changes on the wall clock rather than on a stopwatch.
  def daily? = rotate_at.present?

  # Whose schedule governs this screen. A follower has none of its own — it moves
  # when its leader does — so its own cycle_seconds is a number nothing acts on,
  # and reporting it to a client is a figure the client cannot check.
  def rotation_clock = follower? ? follows_display : self

  # The most recent time this screen was supposed to change, in the app's zone.
  #
  # Computed from the wall clock every time rather than counted forward from the
  # last change, which is the whole reason this is not simply a cycle_seconds of
  # 86400. The rotation job ticks once a minute, so an interval-driven daily
  # screen lands up to a minute late and then sets its next deadline from there:
  # the error compounds, and a change asked for at 3am walks into the evening
  # over a year. An anchor cannot drift, and it self-corrects — if verso is down
  # at 3am and back at 5am the screen changes at 5am rather than skipping a day.
  #
  # TimeWithZone arithmetic on purpose: 1.day moves the wall clock, so the two
  # days a year that are not 86400 seconds long still change at 3am.
  def last_rotation_anchor(now: Time.current)
    local = now.in_time_zone
    todays = local.change(hour: rotate_hour, min: rotate_minute)

    todays <= local ? todays : todays - 1.day
  end

  # When this screen next changes. `now` when it is already overdue, so a client
  # that polls at the wrong moment is told to expect a change rather than to wait.
  def next_rotation_at(now: Time.current)
    clock = rotation_clock
    return now if clock.current_since.nil?

    return clock.current_since + clock.cycle_seconds unless clock.daily?

    anchor = clock.last_rotation_anchor(now: now)
    clock.current_since < anchor ? now : anchor + 1.day
  end

  def seconds_remaining(now: Time.current)
    [ (next_rotation_at(now: now) - now).ceil, 0 ].max
  end

  # How long a piece is up for. A daily screen has no interval to report and a
  # day is the honest answer; cycle_seconds on such a row is left over.
  def cadence_seconds
    clock = rotation_clock
    clock.daily? ? 1.day.to_i : clock.cycle_seconds
  end

  # This screen's schedule, as a person would say it. One sentence covering all
  # three cases, so no view has to work out which of them applies.
  def schedule_description
    return "mirrors #{follows_display.name}" if follower?
    return "once a day at #{rotate_at}" if daily?

    "every #{ActiveSupport::Duration.build(cycle_seconds).inspect}"
  end

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
  #
  # Two kinds of schedule, and they answer different questions. An interval asks
  # how long a picture stays up, which is what a dashboard background wants. An
  # anchor asks what time of day the picture changes, which is what a television
  # wants, because a television is watched at particular hours and being
  # interrupted is the whole complaint.
  def due?(now: Time.current)
    return false if follower?
    return current_since.nil? || current_since < last_rotation_anchor(now: now) if daily?

    current_since.nil? || current_since + cycle_seconds <= now
  end

  # Aspect ratios this screen will accept, derived from its own shape and how
  # much it is willing to crop. Cropping a ratio A to fill a screen of ratio D
  # discards (A-D)/A when A is wider and (D-A)/D when it is narrower; holding
  # both under f gives D*(1-f) .. D/(1-f).
  # The shapes this panel can crop to its own, given a willingness to lose some of
  # the picture. Defaults to the panel's own tolerance; an artwork may supply a
  # larger one for itself — see Artwork#max_crop_fraction.
  def acceptable_aspect_ratios(fraction = max_crop_fraction)
    slack = 1 - fraction
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
    suitable = suitable.merge(croppable_to_shape) if fill?

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

    show!(upcoming, now: now)
  end

  # Put a particular artwork up, on this screen and everything following it.
  #
  # Used by the rotation and by a person choosing from the browse pages, which
  # are the same act: something decides, and the screens are told. Deliberately
  # does not check eligibility — a person looking at a picture and asking for it
  # has better judgement than the aspect-ratio rule, which exists to keep the
  # rotation from choosing badly rather than to overrule a human.
  def show!(artwork, now: Time.current)
    transaction do
      display_events.create!(artwork: artwork, shown_at: now)
      update!(current_artwork: artwork, current_since: now)
      # Picked after the event is recorded, so the piece just shown has spent a
      # slot and will not immediately be chosen again.
      following = pick(now: now)
      update!(next_artwork: following)

      # Followers do not choose. They are told, so that two screens in two rooms
      # are showing the same picture — which is the whole reason to notice a
      # painting on one and read about it on the other.
      followers.each do |follower|
        follower.display_events.create!(artwork: artwork, shown_at: now)
        follower.update!(current_artwork: artwork, next_artwork: following, current_since: now)
      end
    end

    artwork
  end

  # The screen that decides, which is the one a person should be told about and
  # the one a manual choice has to be applied to.
  def self.leader
    active.find { |display| display.follows_display_id.nil? }
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
  # `crop` names the edge to keep when something has to be discarded, and it goes
  # INSIDE resize_to_fill's argument list rather than alongside it. Every top-level
  # key in a transformation is applied as its own image operation, so a stray
  # `crop:` here calls libvips' crop, which wants x, y, width and height and fails
  # with "you supplied 2 arguments, but operation needs 5".
  #
  # Left nil, the arguments are byte-identical to what they were before this
  # existed, which is what keeps every already-generated variant key valid.
  def variant_transformation(crop: nil)
    unless contain?
      fill = crop ? [ width, height, { crop: crop } ] : [ width, height ]

      return { resize_to_fill: fill, format: :jpeg, saver: { quality: 88 } }
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
  # A starred piece comes up twice as often. One named multiplier, applied here,
  # because here is where weight is decided -- see the migration that added
  # `favourite` for why it is not another weight column.
  FAVOURITE_MULTIPLIER = 2

  def weight_for(artwork)
    collection_weight = display_collections.find_by(collection_id: artwork.collection_id)&.weight || 1
    starred = artwork.favourite? ? FAVOURITE_MULTIPLIER : 1

    artwork.weight * collection_weight * starred
  end

  private
    def rotate_hour = rotate_at.to_s.split(":").first.to_i
    def rotate_minute = rotate_at.to_s.split(":").last.to_i

    # Artworks this panel can render when they may be enlarged up to `upscale`.
    #
    # Ceil rather than floor: at 1.0 the two are identical, and above it a
    # rounded-down threshold would admit a piece that lands a pixel short.
    # Artworks this panel can crop to its shape — by its own tolerance, or by the
    # larger one a particular artwork claims for itself.
    #
    # The individual cases are resolved in Ruby and passed in as ids rather than
    # expressed as SQL. The arithmetic is per-row, so as a query it would be a
    # fragment computing bounds from a column, and the set is a handful of artworks
    # somebody decided about by hand. Cheap to load, and legible.
    def croppable_to_shape
      Artwork.where(aspect_ratio: acceptable_aspect_ratios)
             .or(Artwork.where(id: individually_tolerated_ids))
    end

    def individually_tolerated_ids
      Artwork.where.not(max_crop_fraction: nil).pluck(:id, :max_crop_fraction, :aspect_ratio)
        .filter_map do |id, fraction, ratio|
          id if ratio.present? && acceptable_aspect_ratios(fraction).cover?(ratio)
        end
    end

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
