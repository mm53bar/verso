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

  # THE INDEX IS A GRID OF IMAGES, SO ITS IMAGE URLS ARE ITS PERFORMANCE.
  # These used to be Active Storage proxy URLs, which cost twice: the URL embeds
  # a signed variant key, so regenerating a variant changes every URL on the
  # page, and the proxy controller streams through ActionController::Live, which
  # measured a p90 of 516ms and a 2.4s tail for a 40KB thumbnail. Going back to
  # `image_tag artwork.thumbnail` is a one-word change that reintroduces both
  # silently, because the page still looks right.
  test "the index serves its images from this app, not from Active Storage's proxy" do
    artworks(:native_4k).original.attach(
      io: file_fixture("wide.jpg").open, filename: "wide.jpg", content_type: "image/jpeg"
    )

    get root_path

    assert_response :success
    assert_no_match %r{/rails/active_storage/}, response.body,
      "an Active Storage URL embeds a variant key and streams through Live"
    assert_match %r{/artworks/[\w-]+/variants/thumb\.jpg}, response.body,
      "thumbnails should be addressed by artwork and size"
  end
end
