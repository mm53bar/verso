require "test_helper"

# The screen controls are guarded by the Origin header rather than a CSRF token,
# because the kiosk page is framed cross-site and its session cookie is therefore
# third-party and withheld. This is the test that would have caught the 422 on the
# wall: the test environment sets allow_forgery_protection = false, so no
# token-based test could ever have failed.
class SameOriginWriteTest < ActionDispatch::IntegrationTest
  setup do
    @kiosk = displays(:kiosk)
    @artwork = artworks(:native_4k)
  end

  test "a form posted from verso's own page is allowed" do
    post advance_display_path(@kiosk.slug), headers: { "HTTP_ORIGIN" => "http://www.example.com" }

    assert_response :redirect
  end

  test "a post from another site is refused" do
    post advance_display_path(@kiosk.slug), headers: { "HTTP_ORIGIN" => "https://evil.example" }

    assert_response :forbidden
    assert_nil @kiosk.reload.current_artwork,
      "a hostile page must not be able to drive the screens"
  end

  test "a post with no Origin at all is refused" do
    post advance_display_path(@kiosk.slug)

    assert_response :forbidden
  end

  test "the guard covers every write, not just advancing" do
    hostile = { "HTTP_ORIGIN" => "https://evil.example" }

    post show_artwork_on_display_path(@kiosk.slug, @artwork.slug), headers: hostile
    assert_response :forbidden

    post favourite_artwork_path(@artwork.slug), headers: hostile
    assert_response :forbidden
    assert_not_predicate @artwork.reload, :favourite?
  end

  test "reads are untouched by the guard" do
    get artworks_path, headers: { "HTTP_ORIGIN" => "https://evil.example" }

    assert_response :success, "the feed and browse pages are public by design"
  end
end
