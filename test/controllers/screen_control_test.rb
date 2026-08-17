require "test_helper"

# Choosing a picture by hand is the first write in this app, and it is a plain
# same-origin form post. That is what keeps it off the CORS surface: a page on
# the internet cannot drive an app that has no authentication.
class ScreenControlTest < ActionDispatch::IntegrationTest
  setup do
    @kiosk = displays(:kiosk)
    @television = displays(:television)
    # The fixtures leave the television independent; the real one follows. Set it
    # here rather than in the fixture, which other tests lean on as it is.
    @television.update!(follows_display: @kiosk)
    @artwork = artworks(:native_4k)
  end

  test "showing an artwork puts it on the leader and every follower" do
    post show_artwork_on_display_path(@kiosk.slug, @artwork.slug)

    assert_redirected_to artwork_path(@artwork)
    assert_equal @artwork, @kiosk.reload.current_artwork
    assert_equal @artwork, @television.reload.current_artwork,
      "a follower is told, so both rooms show the same picture"
  end

  test "showing an artwork records it, so the history stays true" do
    assert_difference -> { @kiosk.display_events.count }, 1 do
      post show_artwork_on_display_path(@kiosk.slug, @artwork.slug)
    end
  end

  test "a person may choose a picture the rotation would never pick" do
    sketch = artworks(:sketch_panel)          # 1.2351
    @television.update!(render_mode: "fill", max_crop_fraction: 0.10)

    assert_not_includes @kiosk.eligible_artworks, sketch,
      "sanity: outside the television's window, so the rotation cannot choose it"

    post show_artwork_on_display_path(@kiosk.slug, sketch.slug)

    assert_equal sketch, @kiosk.reload.current_artwork,
      "the aspect rule stops the rotation choosing badly; it does not overrule a person"
  end

  test "advancing moves the rotation on" do
    was = @kiosk.current_artwork

    post advance_display_path(@kiosk.slug)

    assert_response :redirect
    assert_not_equal was, @kiosk.reload.current_artwork
  end

  test "the write routes send no cross-origin header" do
    post advance_display_path(@kiosk.slug)

    assert_nil response.headers["Access-Control-Allow-Origin"],
      "a write must not be reachable by script from another origin"
  end

  test "an unknown display or artwork is a 404" do
    post advance_display_path("no-such-screen")
    assert_response :not_found

    post show_artwork_on_display_path(@kiosk.slug, "no-such-artwork")
    assert_response :not_found
  end
end
