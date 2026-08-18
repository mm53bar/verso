require "test_helper"

class KioskControllerTest < ActionDispatch::IntegrationTest
  setup do
    @kiosk = displays(:kiosk)
    @artwork = artworks(:sketch_panel)
    @artwork.original.attach(
      io: file_fixture("landscape.jpg").open, filename: "landscape.jpg", content_type: "image/jpeg"
    )
    @kiosk.update!(current_artwork: @artwork, current_since: Time.current)
  end

  test "shows what is on that screen right now" do
    get kiosk_url(@kiosk.slug)

    assert_response :success
    assert_select "h1", text: "A sketch panel"
    assert_select "body", /Tom Thomson/
  end

  test "an artist biography stands in when the artwork has no story of its own" do
    get kiosk_url(@kiosk.slug)

    assert_select "body", /drowned at Canoe Lake/
  end

  test "says so plainly when there is nothing written at all" do
    @artwork.artist.update!(bio: nil)

    get kiosk_url(@kiosk.slug)

    assert_select "body", /No story written for this one yet/
  end

  test "prefers the long story, and falls back to the spoken blurb" do
    @artwork.update!(blurb: "The spoken sentence.", story: "The long form for a screen.")
    get kiosk_url(@kiosk.slug)
    assert_select "body", /The long form for a screen/

    @artwork.update!(story: nil)
    get kiosk_url(@kiosk.slug)
    assert_select "body", /The spoken sentence/
  end

  test "a screen showing nothing says so rather than erroring" do
    @kiosk.update!(current_artwork: nil)

    get kiosk_url(@kiosk.slug)

    assert_response :success
    assert_select "body", /Nothing is showing/
  end

  test "may be framed by a kiosk on a loopback origin" do
    get kiosk_url(@kiosk.slug)

    csp = response.headers["Content-Security-Policy"]

    assert_includes csp, "frame-ancestors"
    assert_includes csp, "http://127.0.0.1:*"
    assert_nil response.headers["X-Frame-Options"],
      "X-Frame-Options cannot be combined with frame-ancestors and would win"
  end

  test "a relative back path becomes a link that escapes the iframe" do
    get kiosk_url(@kiosk.slug, back: "/echo-show/home")

    assert_select "a[target=_top][href=?]", "/echo-show/home"
  end

  test "no back link is rendered when none was asked for" do
    get kiosk_url(@kiosk.slug)

    assert_select "a[target=_top]", false
  end

  test "an off-site back path is refused" do
    # The app has no authentication, so an unchecked `back` would make any
    # passer-by able to turn a household URL into a redirect to anywhere.
    [ "https://evil.test/phish", "//evil.test", "javascript:alert(1)",
      "http://evil.test", "/\\evil.test" ].each do |hostile|
      get kiosk_url(@kiosk.slug, back: hostile)

      assert_response :success
      assert_select "a[target=_top]", false, "#{hostile.inspect} should not have produced a link"
    end
  end

  test "an unknown display is a 404" do
    get kiosk_url("no-such-screen")

    assert_response :not_found
  end

  # One scroll instead of three fixed bands. Measured on the
  # real page, the old one gave the story 134px of a 486px column and as little
  # as 91px with a long title, while trying to show 1660 characters.
  test "the story page scrolls as one column rather than pinning bands" do
    get kiosk_url(@kiosk.slug)

    assert_response :success
    assert_select "div.overflow-y-auto", 1,
      "one scroll area, not a pinned header and footer around a squeezed middle"
    assert_select "div.overflow-y-auto h1", 1, "the title scrolls with the story"
    assert_select "div.overflow-y-auto footer", 1, "so do the details"
  end

  test "the controls sit on the picture, where they cost the story nothing" do
    get kiosk_url(@kiosk.slug)

    assert_select "figure form[action=?]", advance_display_path(@kiosk.slug)
    assert_select "figure button", { text: /Next/ },
      "a bare arrow on a picture could mean anything; the word carries it"
    assert_select "figure form[action=?]", favourite_artwork_path(@artwork.slug)
  end

  test "the story page drops the collection row" do
    @artwork.update!(current_location: "Rijksmuseum, Amsterdam")

    get kiosk_url(@kiosk.slug)

    assert_select "dt", text: "Where"
    assert_select "dt", { text: "Collection", count: 0 },
      "which verso grouping a piece belongs to is bookkeeping, not a wall label"
  end
end
