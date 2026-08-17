require "test_helper"

# Cartoon wallpapers at native 3840x2160 barely exist, so the 4K television --
# which every screen must agree with, since it is a follower -- was the binding
# constraint that left 6 of 8 cartoons deactivated. Enlargement is allowed per
# collection rather than globally, because how far a picture can be enlarged is a
# fact about the material: flat colour bounded by line invents almost nothing at
# 2x, and a photographed oil painting looks like exactly what it is.
class DisplayUpscaleTest < ActiveSupport::TestCase
  setup do
    @television = displays(:television)   # 3840x2160, contain
    @kiosk = displays(:kiosk)             # 1920x1200, fill
    @cartoons = collections(:cartoons)

    # The fixtures deliberately keep cartoons off the television -- the real one
    # carries them, but other tests lean on that split -- so the link is made
    # here rather than by changing what every other test sees.
    DisplayCollection.create!(display: @television, collection: @cartoons, weight: 3)

    # A 1080p 16:9 cartoon: the shape almost every cartoon wallpaper comes in.
    @hd = Artwork.create!(
      title: "A 1080p cartoon", collection: @cartoons,
      width: 1920, height: 1080, aspect_ratio: 1.7778,
      reviewed: true, active: true
    )
  end

  test "a collection allows no enlargement by default" do
    assert_equal 1, collections(:canon).max_upscale
    assert_not_includes @television.own_eligible_artworks, @hd
  end

  test "doubling the allowance admits a 1080p cartoon to the 4K panel" do
    @cartoons.update!(max_upscale: 2)

    assert_includes @television.own_eligible_artworks, @hd
  end

  test "the allowance is per collection, not global" do
    @cartoons.update!(max_upscale: 2)
    painting = Artwork.create!(
      title: "A 1080p painting", collection: collections(:canon),
      width: 1920, height: 1080, aspect_ratio: 1.7778,
      reviewed: true, active: true
    )

    assert_includes @television.own_eligible_artworks, @hd
    assert_not_includes @television.own_eligible_artworks, painting,
      "enlarging a photographed painting is the case this rule exists to refuse"
  end

  test "it bounds the enlargement rather than removing the floor" do
    @cartoons.update!(max_upscale: 2)
    thumbnail = Artwork.create!(
      title: "A search-result thumbnail", collection: @cartoons,
      width: 474, height: 266, aspect_ratio: 1.782,
      reviewed: true, active: true
    )

    assert_not_includes @television.own_eligible_artworks, thumbnail
    assert_not_includes @kiosk.own_eligible_artworks, thumbnail
  end

  test "a piece one pixel short is still short" do
    @cartoons.update!(max_upscale: 2)
    @hd.update!(width: 1919, height: 1079)

    assert_not_includes @television.own_eligible_artworks, @hd,
      "the threshold rounds up, so it cannot be cleared by rounding"
  end

  test "the collection cannot demand a piece larger than the panel" do
    @cartoons.max_upscale = 0.5

    assert_not_predicate @cartoons, :valid?
  end

  # The eligibility rule promises the panel gets filled. If the pipeline refused
  # to enlarge, admitting these artworks would quietly hand a 4K screen a 1080p
  # rendition instead -- so this asserts the promise end to end rather than
  # trusting that resize_and_pad enlarges.
  test "the rendition really is generated at the panel's full size" do
    @cartoons.update!(max_upscale: 2)
    small = artworks(:cartoon)
    small.original.attach(
      io: file_fixture("wide.jpg").open, filename: "wide.jpg", content_type: "image/jpeg"
    )   # 384x216, far below the panel

    image = Vips::Image.new_from_buffer(
      small.rendition_for(@television).processed.image.download, ""
    )

    assert_equal 3840, image.width
    assert_equal 2160, image.height
  end
end
