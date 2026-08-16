require "test_helper"

class DisplayTest < ActiveSupport::TestCase
  setup do
    @kiosk = displays(:kiosk)
    @television = displays(:television)
  end

  test "aspect ratio comes from the panel's own dimensions" do
    assert_in_delta 1.6, @kiosk.aspect_ratio, 0.0001
    assert_in_delta 1.7778, @television.aspect_ratio, 0.0001
  end

  test "acceptable aspect ratios widen symmetrically with the crop tolerance" do
    range = @kiosk.acceptable_aspect_ratios

    assert_in_delta 1.2, range.begin, 0.001
    assert_in_delta 2.133, range.end, 0.001
  end

  test "a piece the right shape and big enough is eligible" do
    assert_includes @kiosk.eligible_artworks, artworks(:legacy_crop)
  end

  test "a piece too small to fill the panel is not eligible even at the right ratio" do
    legacy = artworks(:legacy_crop)

    assert_includes @television.acceptable_aspect_ratios, legacy.aspect_ratio,
      "the shape is acceptable, so only the size can be disqualifying it"
    assert_not @television.eligible_artworks.include?(legacy),
      "a 1920x1200 crop cannot fill a 3840x2160 panel without upscaling"
  end

  test "a piece too narrow for the panel is not eligible" do
    assert_includes @kiosk.eligible_artworks, artworks(:sketch_panel)
    assert_not @television.eligible_artworks.include?(artworks(:sketch_panel))
  end

  test "a piece too wide for the panel is not eligible" do
    assert_not @kiosk.eligible_artworks.include?(artworks(:panorama))
  end

  test "unreviewed and deactivated pieces are never eligible" do
    assert_not @kiosk.eligible_artworks.include?(artworks(:unreviewed))
    assert_not @kiosk.eligible_artworks.include?(artworks(:deactivated))
  end

  test "a piece is eligible only on screens carrying its collection" do
    cartoon = artworks(:cartoon)

    assert_includes @kiosk.eligible_artworks, cartoon
    assert_not @television.eligible_artworks.include?(cartoon)
  end

  test "eligibility holds when no overrides exist at all" do
    assert_equal 0, DisplayOverride.count
    assert_predicate @kiosk.eligible_artworks, :any?,
      "an empty exception list must not disqualify the whole collection"
  end

  test "an override admits a piece whose collection the screen does not carry" do
    cartoon = artworks(:cartoon)
    DisplayOverride.create!(display: @television, artwork: cartoon, allowed: true)

    assert_includes @television.eligible_artworks, cartoon
  end

  test "an override excludes a piece the screen would otherwise carry" do
    native = artworks(:native_4k)
    DisplayOverride.create!(display: @kiosk, artwork: native, allowed: false)

    assert_not @kiosk.eligible_artworks.include?(native)
  end

  test "an override cannot force a piece that does not fit the panel" do
    sketch = artworks(:sketch_panel)
    DisplayOverride.create!(display: @television, artwork: sketch, allowed: true)

    assert_not @television.eligible_artworks.include?(sketch),
      "an override bypasses collection membership, not physical suitability"
  end

  test "an override cannot force an unreviewed piece onto a screen" do
    unreviewed = artworks(:unreviewed)
    DisplayOverride.create!(display: @television, artwork: unreviewed, allowed: true)

    assert_not @television.eligible_artworks.include?(unreviewed)
  end

  test "weight multiplies the artwork's own by this screen's view of its collection" do
    cartoon = artworks(:cartoon)

    assert_equal 3, @kiosk.weight_for(cartoon)

    cartoon.update!(weight: 2)
    assert_equal 6, @kiosk.weight_for(cartoon)
  end

  test "weight falls back to the artwork's own on a screen with no pairing" do
    assert_equal 1, @television.weight_for(artworks(:cartoon))
  end

  test "a display with no history is due immediately" do
    assert_predicate @kiosk, :due?
  end

  test "a display is due once its cycle has elapsed" do
    @kiosk.update!(current_since: Time.current)

    assert_not @kiosk.due?
    assert @kiosk.due?(now: Time.current + @kiosk.cycle_seconds)
  end

  test "file delivery requires a path to write to" do
    @television.file_path = nil

    assert_not @television.valid?
    assert_includes @television.errors[:file_path], "can't be blank"
  end

  test "http delivery needs no path" do
    assert_predicate @kiosk, :valid?
    assert_nil @kiosk.file_path
  end

  test "delivery must be one verso knows how to perform" do
    @kiosk.delivery = "carrier-pigeon"

    assert_not @kiosk.valid?
  end
end
