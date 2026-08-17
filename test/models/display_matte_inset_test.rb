require "test_helper"

# A matte surrounds a picture. Padding alone cannot do that: it fits the artwork
# to the panel, so anything narrower than the screen meets the top and bottom
# edges exactly and the matte appears only down the sides, which reads as
# letterboxing rather than as a mount board.
class DisplayMatteInsetTest < ActiveSupport::TestCase
  setup do
    @television = displays(:television)   # 3840x2160
    @television.update!(render_mode: "contain", matte_color: "#EDE7DA")
    @artwork = artworks(:native_4k)
    @artwork.original.attach(
      io: file_fixture("landscape.jpg").open, filename: "landscape.jpg",
      content_type: "image/jpeg"
    )   # 400x250, ratio 1.6, narrower than the panel
  end

  test "no inset keeps padding in one step, as before" do
    @television.update!(matte_inset: 0)

    assert_equal [ 3840, 2160 ], @television.variant_transformation[:resize_and_pad].first(2)
    assert_nil @television.variant_transformation[:gravity]
  end

  test "an inset scales the artwork down and centres it on the full panel" do
    @television.update!(matte_inset: 0.05)

    transformation = @television.variant_transformation

    assert_nil transformation[:resize_and_pad],
      "padding to the panel would scale the artwork back up and undo the inset"
    assert_equal [ 3624, 1944 ], transformation[:resize_to_limit]
    assert_equal 3840, transformation[:gravity][1]
    assert_equal 2160, transformation[:gravity][2]
  end

  test "the margin is even, measured off the height on both axes" do
    @television.update!(matte_inset: 0.05)
    inner_width, inner_height = @television.matte_inner_size

    assert_equal (3840 - inner_width) / 2, (2160 - inner_height) / 2,
      "a mount board has the same border on every side"
  end

  test "the rendered image really has matte on all four sides" do
    @television.update!(matte_inset: 0.05)

    image = Vips::Image.new_from_buffer(
      @artwork.rendition_for(@television).processed.image.download, ""
    )

    assert_equal 3840, image.width
    assert_equal 2160, image.height

    matte = [ 237, 231, 218 ]
    # The middle of each edge: the two that padding alone would have left as
    # artwork are top and bottom.
    assert_in_delta matte[0], image.getpoint(1920, 4).first, 6, "no matte along the top"
    assert_in_delta matte[0], image.getpoint(1920, 2155).first, 6, "no matte along the bottom"
    assert_in_delta matte[0], image.getpoint(4, 1080).first, 6, "no matte down the left"
    assert_in_delta matte[0], image.getpoint(3835, 1080).first, 6, "no matte down the right"
  end

  test "an inset that would swallow the panel is refused" do
    @television.matte_inset = 0.25

    assert_not_predicate @television, :valid?
  end
end
