require "test_helper"

class ArtworkTest < ActiveSupport::TestCase
  test "aspect ratio is derived on save, not set by hand" do
    artwork = Artwork.create!(title: "Derived", collection: collections(:canon),
                              width: 3840, height: 2160)

    assert_in_delta 1.7778, artwork.aspect_ratio, 0.0001
  end

  test "aspect ratio is nil until dimensions are known" do
    artwork = Artwork.create!(title: "No bytes yet", collection: collections(:canon))

    assert_nil artwork.aspect_ratio
  end

  test "aspect ratio follows a re-import at a different size" do
    artwork = artworks(:legacy_crop)
    artwork.update!(width: 3840, height: 2160)

    assert_in_delta 1.7778, artwork.aspect_ratio, 0.0001
  end

  test "slug combines artist and title" do
    artwork = Artwork.create!(title: "The Jack Pine", artist: artists(:thomson),
                              collection: collections(:canadian))

    assert_equal "tom-thomson-the-jack-pine", artwork.slug
  end

  test "slug falls back to the source filename when there is no title" do
    artwork = Artwork.create!(collection: collections(:cartoons),
                              source_file: "some-unidentified-wallpaper.jpg")

    assert_equal "some-unidentified-wallpaper", artwork.slug
  end

  test "slug is unique even when two pieces share a name" do
    2.times { Artwork.create!(title: "Landscape", collection: collections(:canon)) }

    assert_equal %w[ landscape landscape-2 ], Artwork.where(title: "Landscape").order(:id).pluck(:slug)
  end

  test "slug survives a title correction" do
    artwork = Artwork.create!(title: "Wrong title", collection: collections(:canon))
    original_slug = artwork.slug

    artwork.update!(title: "Correct title")

    assert_equal original_slug, artwork.slug,
      "clients cache feed URLs; a changed slug reads as a different artwork"
  end

  test "an untitled piece says so rather than inventing a title" do
    assert_equal "Untitled", artworks(:cartoon).display_title
    assert_nil artworks(:cartoon).title
  end

  test "fills? is true only when the original covers the panel in both dimensions" do
    assert artworks(:native_4k).fills?(displays(:television))
    assert artworks(:native_4k).fills?(displays(:kiosk))
    assert_not artworks(:legacy_crop).fills?(displays(:television))
  end

  test "fills? is false when the dimensions are unknown" do
    artwork = Artwork.create!(title: "No bytes yet", collection: collections(:canon))

    assert_not artwork.fills?(displays(:kiosk))
  end

  test "eligible requires both reviewed and active" do
    assert_includes Artwork.eligible, artworks(:native_4k)
    assert_not Artwork.eligible.include?(artworks(:unreviewed))
    assert_not Artwork.eligible.include?(artworks(:deactivated))
  end

  test "an artwork may have no artist" do
    assert_nil artworks(:cartoon).artist
    assert_predicate artworks(:cartoon), :valid?
  end

  test "titles are squished and blanks become nil" do
    artwork = Artwork.create!(title: "  The   Jack Pine  ", collection: collections(:canon))
    assert_equal "The Jack Pine", artwork.title

    artwork.update!(title: "   ")
    assert_nil artwork.title
  end
end
