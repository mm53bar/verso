require "test_helper"

# The television crops, and because the kiosk may only pick what its follower can
# also render, this one screen's tolerance decides the whole collection. The
# number is the TOTAL share of the picture discarded, not the share per edge:
# centred, 10% means 5% off the top and 5% off the bottom.
class DisplayFitWindowTest < ActiveSupport::TestCase
  setup do
    @television = displays(:television)
    @television.update!(render_mode: "fill", max_crop_fraction: 0.10)
  end

  test "the window is exactly the share of the picture a crop would discard" do
    window = @television.acceptable_aspect_ratios

    # 3840/2160 = 1.7778. Losing a tenth of the height puts the floor at 1.6;
    # losing a tenth of the width puts the ceiling at 1.975.
    assert_in_delta 1.6, window.first, 0.001
    assert_in_delta 1.9753, window.last, 0.001
  end

  test "a picture at the boundary loses the fraction the window names" do
    [ window_floor, window_ceiling ].each do |ratio|
      panel = @television.aspect_ratio
      lost = ratio < panel ? 1 - ratio / panel : 1 - panel / ratio

      assert_in_delta 0.10, lost, 0.001,
        "#{ratio.round(3)} sits on the boundary, so it should lose exactly the tolerance"
    end
  end

  test "a sketch panel is outside the window and simply is not picked" do
    sketch = artworks(:sketch_panel)   # 1.2351

    assert_not_includes @television.own_eligible_artworks, sketch
    assert_predicate sketch.reload, :active?,
      "excluded by the rule, not by deactivating it — widening the window brings it back"
  end

  test "widening the window brings it straight back" do
    sketch = artworks(:sketch_panel)
    @television.update!(max_crop_fraction: 0.32)

    assert_includes @television.own_eligible_artworks, sketch
  end

  private
    def window_floor = @television.acceptable_aspect_ratios.first

    def window_ceiling = @television.acceptable_aspect_ratios.last
end
