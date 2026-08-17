require "test_helper"

# Search is server-side, which is a deliberate divergence from nosh's
# client-side filter: this index is paged at 48, so filtering the rendered page
# would silently answer "no matches" for anything on page 2.
class ArtworkSearchTest < ActionDispatch::IntegrationTest
  test "finds an artwork by its own title" do
    get artworks_path(q: "panorama")

    assert_response :success
    assert_includes response.body, artworks(:panorama).display_title
  end

  test "finds an artwork by its artist, not just its own columns" do
    match = artworks(:sketch_panel)

    get artworks_path(q: "thomson")

    assert_includes response.body, match.display_title
    assert_not_includes response.body, artworks(:panorama).display_title,
      "searching an artist's name should not return everything"
  end

  test "finds an artwork by its collection" do
    get artworks_path(q: "cartoons")

    assert_response :success
    assert_includes response.body, artworks(:cartoon).display_title
  end

  test "the count reports the whole match, not just the page shown" do
    get artworks_path(q: "a")

    # This is the property a client-side filter over one page cannot have.
    assert_select "p", text: /#{Artwork.matching("a").count} artworks matching/
  end

  test "a wildcard in the query is a literal, not a match-everything" do
    get artworks_path(q: "%")

    assert_response :success
    assert_select "p", text: /Nothing matches that/
  end

  test "an empty query returns the whole collection" do
    get artworks_path(q: "   ")

    assert_response :success
    assert_select "p", text: /#{Artwork.count} artworks/
  end

  test "the query survives into the filter links" do
    get artworks_path(q: "thomson")

    assert_select "a[href*='q=thomson']", { minimum: 1 },
      "a filter link that drops the query silently clears the search"
  end

  test "results come back inside the frame the input targets" do
    get artworks_path(q: "panorama")

    assert_select "turbo-frame#collection", 1
  end
end
