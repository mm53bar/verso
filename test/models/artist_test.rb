require "test_helper"

class ArtistTest < ActiveSupport::TestCase
  test "slug comes from the name" do
    assert_equal "emily-carr", Artist.create!(name: "Emily Carr").slug
  end

  test "a name is required" do
    assert_not Artist.new.valid?
  end

  test "names are squished" do
    assert_equal "Emily Carr", Artist.create!(name: "  Emily   Carr ").name
  end

  test "lifespan reads as a range, and is absent when unknown" do
    assert_equal "1877–1917", artists(:thomson).lifespan
    assert_nil Artist.create!(name: "Anonymous").lifespan
  end

  test "deleting an artist orphans the work rather than destroying it" do
    thomson = artists(:thomson)
    artwork = artworks(:sketch_panel)

    assert_no_difference -> { Artwork.count } do
      thomson.destroy!
    end

    assert_nil artwork.reload.artist_id
  end
end
