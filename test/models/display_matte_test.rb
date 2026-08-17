require "test_helper"

# Matting rather than cropping is what lets two differently-shaped screens show
# the same picture. Measured on the real collection (2026-08-16), it took the
# set both screens could share from 76 artworks to 117, and the Canadian
# collection within that from 5 to 28 — because a Group of Seven sketch panel is
# 1.235 and cropping one to 16:9 throws away a third of the painting.
class DisplayMatteTest < ActiveSupport::TestCase
  setup do
    @television = displays(:television)
    @television.update!(render_mode: "contain")
  end

  test "a picture too narrow to crop to 16:9 can still be matted into it" do
    sketch = artworks(:sketch_panel)   # 3840x3109, ratio 1.2351

    assert_includes @television.own_eligible_artworks, sketch
    assert_not displays(:kiosk).acceptable_aspect_ratios.cover?(0),
      "sanity: the kiosk still has a bounded range"

    @television.update!(render_mode: "fill")
    assert_not @television.own_eligible_artworks.include?(sketch),
      "cropping to fill should still reject it — that is the whole difference"
  end

  test "a picture too wide to crop can also be matted" do
    panorama = artworks(:panorama)     # 5000x1400, ratio 3.5714

    assert_includes @television.own_eligible_artworks, panorama

    @television.update!(render_mode: "fill")
    assert_not @television.own_eligible_artworks.include?(panorama)
  end

  test "matting still refuses to enlarge, on the limiting dimension only" do
    # 1920x1200 is wider than it is tall relative to 16:9, so height limits it
    # and 1200 < 2160. Matting is laxer than cropping, not unlimited.
    assert_not @television.own_eligible_artworks.include?(artworks(:legacy_crop))
  end

  test "a wide picture is limited by width, a tall one by height" do
    wide = Artwork.create!(title: "Wide enough", collection: collections(:canon),
                           width: 3840, height: 1200)   # ratio 3.2, needs width
    tall = Artwork.create!(title: "Tall enough", collection: collections(:canon),
                           width: 2400, height: 2160)   # ratio 1.11, needs height
    [ wide, tall ].each { |a| a.update!(reviewed: true) }

    assert_includes @television.own_eligible_artworks, wide
    assert_includes @television.own_eligible_artworks, tall
  end

  test "the rendition is padded to the panel, not cropped to it" do
    sketch = artworks(:sketch_panel)
    sketch.original.attach(
      io: file_fixture("landscape.jpg").open, filename: "landscape.jpg", content_type: "image/jpeg"
    )

    image = Vips::Image.new_from_buffer(sketch.rendition_for(@television).processed.download, "")

    assert_equal @television.width, image.width
    assert_equal @television.height, image.height
  end

  test "the matte colour is parsed for libvips, and a bad one does not explode" do
    assert_equal [ 17, 17, 17 ], @television.matte_rgb

    @television.update!(matte_color: "#ff8000")
    assert_equal [ 255, 128, 0 ], @television.matte_rgb

    @television.update_column(:matte_color, "not a colour")
    assert_equal [ 17, 17, 17 ], @television.reload.matte_rgb
  end

  test "fill and contain ask for different transformations" do
    assert @television.variant_transformation.key?(:resize_and_pad)
    assert displays(:kiosk).variant_transformation.key?(:resize_to_fill)
  end

  test "render mode must be one verso knows how to perform" do
    @television.render_mode = "stretch"

    assert_not @television.valid?
  end
end
