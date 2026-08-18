require "test_helper"

# Where a picture loses itself when it has to be cropped.
class ArtworkCropTest < ActiveSupport::TestCase
  setup do
    @kiosk = displays(:kiosk)             # 1920x1200, 1.60, fill
    @television = displays(:television)   # 3840x2160, 1.7778, fill
    @tall = artworks(:sketch_panel)       # 1.2351 — narrower than both, so both crop its height
    @wide = artworks(:panorama)           # 3.5714 — wider than both, so both crop its width
  end

  # THE GUARANTEE THIS FEATURE HAS TO KEEP.
  # The transformation hash is the Active Storage variant key. If an artwork that
  # expressed no preference produced even a syntactically different hash — a
  # `crop: :centre` meaning exactly what the default already means — every
  # rendition in the collection would get a new key and be regenerated to produce
  # identical bytes. Nothing that has not opted in may move.
  test "an artwork with no preference produces the untouched transformation" do
    [ @kiosk, @television ].each do |display|
      assert_nil @tall.crop_focus_x
      assert_nil @tall.crop_focus_y
      assert_nil @tall.crop_edge_for(display)

      assert_equal display.variant_transformation,
        display.variant_transformation(crop: @tall.crop_edge_for(display)),
        "a no-preference artwork must not change its own variant key"
      assert_equal [ display.width, display.height ],
        display.variant_transformation[:resize_to_fill],
        "no options hash should appear in the arguments at all"
    end
  end

  test "centre is spelled out in the database but still sends nothing to libvips" do
    @tall.update!(crop_focus_y: "centre")

    assert_nil @tall.crop_edge_for(@television)
  end

  test "keeping the bottom asks libvips for the high edge" do
    @tall.update!(crop_focus_y: "bottom")

    assert_equal :high, @tall.crop_edge_for(@television)
    assert_equal [ 3840, 2160, { crop: :high } ],
      @television.variant_transformation(crop: :high)[:resize_to_fill]
  end

  test "keeping the top asks libvips for the low edge" do
    @tall.update!(crop_focus_y: "top")

    assert_equal :low, @tall.crop_edge_for(@television)
  end

  # The axis is computed from the two shapes, so the irrelevant preference is
  # ignored rather than applied to the wrong edge. libvips takes one value and
  # would happily read a horizontal preference as a vertical one.
  test "a horizontal preference is ignored when the crop is vertical" do
    @tall.update!(crop_focus_x: "left")

    assert_nil @tall.crop_edge_for(@television),
      "this artwork is narrower than the panel, so its width is not what is lost"
  end

  test "a vertical preference is ignored when the crop is horizontal" do
    @wide.update!(crop_focus_y: "top")

    assert_nil @wide.crop_edge_for(@kiosk),
      "this artwork is wider than the panel, so its height is not what is lost"
  end

  test "keeping the left of a picture too wide for the panel" do
    @wide.update!(crop_focus_x: "left")

    assert_equal :low, @wide.crop_edge_for(@kiosk)
    assert_equal :low, @wide.crop_edge_for(@television)
  end

  # The same artwork can be cropped on different axes by two screens, which is
  # the whole reason there are two columns rather than one.
  test "one artwork can lose its width on one screen and its height on another" do
    native = artworks(:native_4k) # 1.7778 — matches the television, wider than the kiosk
    native.update!(crop_focus_x: "right", crop_focus_y: "top")

    assert_equal :high, native.crop_edge_for(@kiosk),
      "1.7778 into 1.60 crops the width, so the x preference applies"
    assert_equal :low, native.crop_edge_for(@television),
      "1.7778 into 1.7778 crops nothing, and the y branch is the harmless one"
  end

  test "a matting display never crops, so it never consults a preference" do
    @television.update!(render_mode: "contain")
    @tall.update!(crop_focus_y: "bottom")

    assert_nil @tall.crop_edge_for(@television)
  end

  test "an artwork of unknown proportions expresses no preference" do
    @tall.update!(crop_focus_y: "bottom")
    @tall.update_column(:aspect_ratio, nil)

    assert_nil @tall.reload.crop_edge_for(@television)
  end

  test "only the named edges are accepted" do
    assert_not @tall.update(crop_focus_y: "middle")
    @tall.reload
    assert_not @tall.update(crop_focus_x: "top"),
      "top is a vertical edge and does not belong in the horizontal column"
    @tall.reload
    assert @tall.update(crop_focus_y: "bottom")
    assert @tall.update(crop_focus_x: nil)
  end

  # The options above are only worth anything if they reach libvips and change the
  # pixels. Built rather than fixtured: this needs an image whose halves are
  # tellingly different, and a synthetic one says exactly what it is.
  test "the preference changes which half of the image survives" do
    artwork = artworks(:native_4k)
    artwork.original.attach(io: two_tone_image, filename: "two_tone.jpg",
                            content_type: "image/jpeg")

    dark_kept = mean_brightness(artwork, crop_focus_y: "top")
    light_kept = mean_brightness(artwork, crop_focus_y: "bottom")

    assert_operator light_kept, :>, dark_kept + 20,
      "keeping the bottom of a dark-topped picture should be visibly brighter"
  end

  # ---- the fingerprint that carries a crop change to the screens ----

  test "the fingerprint changes when the crop changes" do
    attach_image(@tall)
    before = @tall.rendition_fingerprint(@television)
    @tall.update!(crop_focus_y: "bottom")
    after = @tall.rendition_fingerprint(@television)

    assert_not_equal before, after,
      "nothing downstream can notice a new crop if this does not move"
  end

  test "the fingerprint is stable when nothing about the image changed" do
    attach_image(@tall)
    @tall.update!(crop_focus_y: "bottom")
    first = @tall.rendition_fingerprint(@television)
    @tall.update!(title: "Renamed, but the same picture")

    assert_equal first, @tall.rendition_fingerprint(@television),
      "a stable url is the point; this must not churn on unrelated edits"
  end

  test "the fingerprint differs per display, because the bytes do" do
    attach_image(@tall)

    assert_not_equal @tall.rendition_fingerprint(@kiosk),
      @tall.rendition_fingerprint(@television)
  end

  test "an artwork with no image has no fingerprint" do
    assert_nil artworks(:cartoon).rendition_fingerprint(@television)
  end

  # THE REASON IT IS DERIVED RATHER THAN READ.
  # This runs on every feed request, and three clients poll every 60 seconds.
  # Naming the bytes by their checksum would mean generating the variant first,
  # which on this collection means minutes of libvips on a cold cache.
  test "naming the bytes does not generate them" do
    artwork = artworks(:native_4k)
    artwork.original.attach(io: two_tone_image, filename: "two_tone.jpg",
                            content_type: "image/jpeg")

    assert_no_difference -> { ActiveStorage::VariantRecord.count } do
      assert_not_nil artwork.rendition_fingerprint(@television)
    end
  end

  private
    def attach_image(artwork)
      artwork.original.attach(io: file_fixture("landscape.jpg").open,
                              filename: "landscape.jpg", content_type: "image/jpeg")
    end

    # 2000x4000, black on top and near-white below, so which half survived a
    # vertical crop is unambiguous from a single number.
    def two_tone_image
      dark = Vips::Image.black(2000, 2000, bands: 3)
      light = dark + 240

      StringIO.new(dark.join(light, :vertical).jpegsave_buffer(Q: 90))
    end

    # The television is 1.7778 and the image is 0.5, so the crop is vertical.
    def mean_brightness(artwork, focus)
      artwork.update!(focus)
      artwork.update_column(:aspect_ratio, 0.5)
      blob = artwork.reload.rendition_for(displays(:television)).processed.image

      Vips::Image.new_from_buffer(blob.download, "").avg
    end
end
