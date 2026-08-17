require "test_helper"

class FavouriteControlTest < ActionDispatch::IntegrationTest
  setup { @artwork = artworks(:native_4k) }

  test "the star toggles" do
    post favourite_artwork_path(@artwork.slug)
    assert_predicate @artwork.reload, :favourite?

    post favourite_artwork_path(@artwork.slug)
    assert_not_predicate @artwork.reload, :favourite?
  end

  test "it says what the star actually does" do
    post favourite_artwork_path(@artwork.slug)

    assert_match(/twice as often/, flash[:notice],
      "a star with an unexplained effect is a mystery button")
  end

  test "starring is a write, so it carries no cross-origin header" do
    post favourite_artwork_path(@artwork.slug)

    assert_nil response.headers["Access-Control-Allow-Origin"]
  end

  test "the wall can star whatever is on it" do
    @kiosk = displays(:kiosk)
    @kiosk.update!(current_artwork: @artwork, current_since: Time.current)

    get kiosk_path(@kiosk.slug)

    assert_response :success
    assert_select "form[action=?]", favourite_artwork_path(@artwork.slug)
  end

  test "an unknown artwork is a 404" do
    post favourite_artwork_path("no-such-thing")

    assert_response :not_found
  end
end
