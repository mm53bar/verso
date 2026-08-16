require "test_helper"

class DisplayRotationTest < ActiveSupport::TestCase
  setup do
    @kiosk = displays(:kiosk)
    # Every eligible piece needs bytes: rotation picks them, delivery renders them.
    @kiosk.eligible_artworks.each { |artwork| attach(artwork) }
  end

  test "advancing records what is showing and when" do
    now = Time.current
    artwork = @kiosk.advance!(now: now)

    assert_equal artwork, @kiosk.current_artwork
    assert_in_delta now.to_f, @kiosk.current_since.to_f, 1
    assert_equal 1, @kiosk.display_events.count
    assert_equal artwork, @kiosk.display_events.first.artwork
  end

  test "advancing lines up what comes next, and honours it" do
    @kiosk.advance!
    upcoming = @kiosk.next_artwork

    assert_not_nil upcoming
    assert_not_equal @kiosk.current_artwork, upcoming,
      "preloading the picture already on screen is pointless"

    assert_equal upcoming, @kiosk.advance!, "the committed next must actually be shown next"
  end

  test "a next artwork that stopped being eligible is dropped rather than shown" do
    @kiosk.advance!
    upcoming = @kiosk.next_artwork
    upcoming.update!(active: false)

    shown = @kiosk.advance!

    assert_not_equal upcoming, shown
    assert_includes @kiosk.eligible_artworks, shown
  end

  test "everything eligible is shown before anything repeats" do
    eligible = @kiosk.eligible_artworks.to_a
    slots = eligible.sum { |artwork| @kiosk.weight_for(artwork) }

    shown = Array.new(slots) { @kiosk.advance! }

    assert_equal eligible.map(&:id).sort, shown.map(&:id).uniq.sort,
      "a full round must cover the whole eligible collection"

    eligible.each do |artwork|
      assert_equal @kiosk.weight_for(artwork), shown.count(artwork),
        "#{artwork.slug} should appear once per unit of weight in a round"
    end
  end

  test "a new round starts once every slot is spent" do
    # advance! looks one pick ahead, so the round rolls over during the lookahead
    # of the last showing rather than after it. Measure from the first round to
    # a full round later rather than trying to name the exact boundary.
    start = Time.current
    @kiosk.advance!(now: start)
    first_round = @kiosk.round_started_at
    slots = @kiosk.eligible_artworks.sum { |artwork| @kiosk.weight_for(artwork) }

    slots.times { |i| @kiosk.advance!(now: start + (i + 1).hours) }

    assert_operator @kiosk.round_started_at, :>, first_round
  end

  test "weight makes a piece appear more often, per screen" do
    cartoon = artworks(:cartoon)
    assert_equal 3, @kiosk.weight_for(cartoon)

    slots = @kiosk.eligible_artworks.sum { |artwork| @kiosk.weight_for(artwork) }
    shown = Array.new(slots) { @kiosk.advance! }

    assert_equal 3, shown.count(cartoon)
    assert_equal 1, shown.count(artworks(:native_4k))
  end

  test "a display with nothing eligible keeps its current image rather than blanking" do
    empty = Display.create!(name: "Unpaired screen", width: 1920, height: 1200, cycle_seconds: 60)

    assert_nil empty.advance!
    assert_nil empty.current_artwork
  end

  test "due? respects the cycle, and a fresh display is due at once" do
    assert_predicate @kiosk, :due?

    @kiosk.advance!(now: Time.current)

    assert_not @kiosk.due?
    assert @kiosk.due?(now: @kiosk.current_since + @kiosk.cycle_seconds)
  end

  private
    def attach(artwork)
      return if artwork.original.attached?

      artwork.original.attach(
        io: file_fixture("landscape.jpg").open, filename: "landscape.jpg", content_type: "image/jpeg"
      )
    end
end
