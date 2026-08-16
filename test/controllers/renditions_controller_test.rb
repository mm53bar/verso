require "test_helper"

class RenditionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @artwork = artworks(:native_4k)
    @artwork.original.attach(
      io: file_fixture("wide.jpg").open, filename: "wide.jpg", content_type: "image/jpeg"
    )
    @kiosk = displays(:kiosk)
  end

  test "serves the artwork cropped to fill the display" do
    get artwork_rendition_url(@artwork.slug, @kiosk.slug)

    assert_response :success
    assert_equal "image/jpeg", response.media_type

    image = Vips::Image.new_from_buffer(response.body, "")
    assert_equal @kiosk.width, image.width
    assert_equal @kiosk.height, image.height
  end

  test "the same artwork is cropped differently for a different display" do
    get artwork_rendition_url(@artwork.slug, displays(:television).slug)

    image = Vips::Image.new_from_buffer(response.body, "")

    assert_equal 3840, image.width
    assert_equal 2160, image.height
  end

  test "streams the bytes rather than redirecting" do
    get artwork_rendition_url(@artwork.slug, @kiosk.slug)

    assert_response :success
    assert_not response.redirect?,
      "a redirect costs a second round trip at the moment a screen is swapping"
  end

  test "is cacheable forever, because the url names one artwork at one size" do
    get artwork_rendition_url(@artwork.slug, @kiosk.slug)

    assert_includes response.headers["Cache-Control"], "immutable"
    assert_includes response.headers["Cache-Control"], "public"
  end

  test "an artwork with no bytes is a 404 rather than an error" do
    get artwork_rendition_url(artworks(:cartoon).slug, @kiosk.slug)

    assert_response :not_found
  end

  test "unknown artwork or display is a 404" do
    get artwork_rendition_url("no-such-artwork", @kiosk.slug)
    assert_response :not_found

    get artwork_rendition_url(@artwork.slug, "no-such-display")
    assert_response :not_found
  end
end
