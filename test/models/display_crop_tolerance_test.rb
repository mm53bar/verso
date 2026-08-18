require "test_helper"

# A particular picture being worth a harder crop than pictures in general.
class DisplayCropToleranceTest < ActiveSupport::TestCase
  setup do
    # 1.7778 at a 0.25 tolerance, so it accepts 1.3333 and up.
    @television = displays(:television)
    # 1.2351, in a collection the television carries, large enough for it, and
    # refused on shape alone. Reaching 1.7778 from there costs 30.5% of the height.
    @narrow = artworks(:sketch_panel)
  end

  test "a picture below the panel's floor is refused by default" do
    assert_nil @narrow.max_crop_fraction
    assert_operator @narrow.aspect_ratio, :<, @television.acceptable_aspect_ratios.begin
    assert_not @television.own_eligible_artworks.exists?(id: @narrow.id)
  end

  test "a picture may claim a harder crop for itself" do
    @narrow.update!(max_crop_fraction: 0.32)

    assert @television.own_eligible_artworks.exists?(id: @narrow.id),
      "0.32 covers the 30.5% this picture needs, so the television should take it"
  end

  test "a tolerance that still does not reach is no help" do
    @narrow.update!(max_crop_fraction: 0.28)

    assert_not @television.own_eligible_artworks.exists?(id: @narrow.id),
      "0.28 leaves a floor of 1.28, and this picture is 1.2351"
  end

  # THE WHOLE REASON THIS IS PER ARTWORK.
  # Raising the television's own tolerance to 0.32 would have admitted this piece
  # and everything else sitting between the two floors — about thirty six artworks
  # in the real collection, none of whose crops anybody had looked at.
  test "one picture's tolerance admits only that picture" do
    before = @television.own_eligible_artworks.pluck(:id).sort
    @narrow.update!(max_crop_fraction: 0.32)
    after = @television.own_eligible_artworks.pluck(:id).sort

    assert_equal (before + [ @narrow.id ]).sort, after,
      "a tolerance on one artwork must not widen the panel for the rest"
  end

  test "the panel's own tolerance still applies to everything else" do
    @narrow.update!(max_crop_fraction: 0.32)
    other = artworks(:panorama) # 3.5714, too wide, and claims nothing

    assert_not @television.own_eligible_artworks.exists?(id: other.id)
  end

  test "a matting display has no aspect floor to waive" do
    @television.update!(render_mode: "contain")

    assert @television.own_eligible_artworks.exists?(id: @narrow.id),
      "contain scales the whole picture in, so shape was never the question"
  end

  test "the window can be asked for at any tolerance" do
    default = @television.acceptable_aspect_ratios
    wider = @television.acceptable_aspect_ratios(0.32)

    assert_operator wider.begin, :<, default.begin
    assert_operator wider.end, :>, default.end
    assert_in_delta 1.3333, default.begin, 0.001
    assert_in_delta 1.2093, wider.begin, 0.001
  end

  test "the tolerance must be a fraction" do
    assert_not @narrow.update(max_crop_fraction: 1)
    @narrow.reload
    assert_not @narrow.update(max_crop_fraction: -0.1)
    @narrow.reload
    assert @narrow.update(max_crop_fraction: 0.32)
    assert @narrow.update(max_crop_fraction: nil)
  end

  # An artwork with no dimensions cannot be measured against anything, and must not
  # crash the query that every rotation runs.
  test "a tolerance on an unmeasured artwork is ignored, not fatal" do
    @narrow.update!(max_crop_fraction: 0.32)
    @narrow.update_column(:aspect_ratio, nil)

    assert_nothing_raised { @television.own_eligible_artworks.count }
    assert_not @television.own_eligible_artworks.exists?(id: @narrow.id)
  end
end
