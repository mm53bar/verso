require "test_helper"

class ArtworksControllerTest < ActionDispatch::IntegrationTest
  test "the index pages rather than rendering the whole collection at once" do
    get artworks_url

    assert_response :success
    assert_select "li", maximum: ArtworksController::PER_PAGE
  end

  test "a page beyond the last clamps rather than showing an empty grid" do
    get artworks_url(page: 9999)

    assert_response :success
    assert_select "li", minimum: 1
  end

  test "a nonsense page number is treated as the first" do
    get artworks_url(page: "-3")

    assert_response :success
  end

  test "filtering by collection narrows the count and survives paging" do
    get artworks_url(collection: collections(:canon).slug)

    assert_response :success
    assert_select "body", /#{collections(:canon).artworks.count} artwork/
  end

  test "an artwork page says which screens can show it" do
    get artwork_url(artworks(:native_4k))

    assert_response :success
    assert_select "h1", text: "A native 4K landscape"
  end

  test "an artwork no screen can show says so plainly" do
    get artwork_url(artworks(:panorama))

    assert_response :success
    assert_select "body", /Not eligible for any screen/
  end
end
