require "test_helper"

class ArtworkImporterTest < ActiveSupport::TestCase
  NO_WAIT = ->(_attempt) { 0 }

  test "imports an artwork and attaches the original" do
    result = import(title: "A Bar at the Folies-Bergère", collection: "Wikimedia canon")

    assert_predicate result, :success?
    assert_predicate result.artwork.original, :attached?
    assert_equal "Wikimedia canon", result.artwork.collection.name
  end

  test "dimensions are read from the image, not taken on trust from the payload" do
    result = import(title: "Lying payload", collection: "Wikimedia canon",
                    width: 9999, height: 1)

    assert_equal 400, result.artwork.width
    assert_equal 250, result.artwork.height
    assert_in_delta 1.6, result.artwork.aspect_ratio, 0.0001
  end

  test "an artist given as a bare name is found or created" do
    result = import(title: "The West Wind", artist: "Tom Thomson", collection: "Canadian")

    assert_equal artists(:thomson), result.artwork.artist
    assert_no_difference -> { Artist.count } do
      import(title: "Another one", artist: "Tom Thomson", collection: "Canadian")
    end
  end

  test "an artist given as a full record carries its biography" do
    result = import(title: "Vue", collection: "Wikimedia canon", artist: {
      "name" => "Berthe Morisot", "birth_year" => 1841, "death_year" => 1895,
      "nationality" => "French", "bio" => "A founding member of the Impressionists."
    })

    artist = result.artwork.artist

    assert_equal "Berthe Morisot", artist.name
    assert_equal 1841, artist.birth_year
    assert_equal "A founding member of the Impressionists.", artist.bio
  end

  test "an artwork may be imported with no artist at all" do
    result = import(title: "A cartoon", collection: "Cartoons")

    assert_predicate result, :success?
    assert_nil result.artwork.artist
  end

  test "an unknown collection is created, a known one is reused" do
    assert_difference -> { Collection.count }, 1 do
      import(title: "First", collection: "Photography")
    end

    assert_no_difference -> { Collection.count } do
      import(title: "Second", collection: "Photography")
    end
  end

  test "a collection is required" do
    result = import(title: "Homeless")

    assert_not result.success?
    assert_equal "collection is required", result.error
    assert_nil result.artwork
  end

  test "bookkeeping the source happens to carry is ignored rather than fatal" do
    result = import(title: "Ranked", collection: "Wikimedia canon",
                    sitelinks: 39, mount_cropped: nil, some_future_key: "whatever")

    assert_predicate result, :success?
    assert_equal "Ranked", result.artwork.title
  end

  test "slug is derived from artist and title" do
    result = import(title: "The Jack Pine", artist: "Tom Thomson", collection: "Canadian")

    assert_equal "tom-thomson-the-jack-pine", result.artwork.slug
  end

  test "an explicit slug updates that artwork in place" do
    first = import(title: "Original title", collection: "Wikimedia canon", slug: "fixed-slug")

    assert_no_difference -> { Artwork.count } do
      second = import(title: "Corrected title", collection: "Wikimedia canon", slug: "fixed-slug")

      assert_equal first.artwork.id, second.artwork.id
      assert_equal "Corrected title", second.artwork.reload.title
    end
  end

  test "imports bytes from a path on disk" do
    result = ArtworkImporter.new({
      title: "From disk", collection: "Wikimedia canon",
      image_path: file_fixture("wide.jpg").to_s
    }).call

    assert_predicate result, :success?
    assert_equal 384, result.artwork.width
  end

  test "an unreadable path is reported, not raised" do
    result = ArtworkImporter.new({
      title: "Missing", collection: "Wikimedia canon", image_path: "/no/such/file.jpg"
    }).call

    assert_not result.success?
    assert_match(/couldn't read/, result.error)
  end

  test "an artwork with no image source at all is reported" do
    result = ArtworkImporter.new({ title: "Bodiless", collection: "Wikimedia canon" }).call

    assert_not result.success?
    assert_match(/no image source/, result.error)
  end

  test "a non-http image_url is rejected before any request is made" do
    result = ArtworkImporter.new({
      title: "Local file", collection: "Wikimedia canon", image_url: "file:///etc/passwd"
    }).call

    assert_not result.success?
    assert_match(/must be http/, result.error)
  end

  test "a failing fetch is retried and then reported" do
    # A port nothing listens on refuses immediately, so this exercises the real
    # retry path against the real dependency rather than a mocked one.
    result = ArtworkImporter.new(
      { title: "Unreachable", collection: "Wikimedia canon",
        image_url: "http://127.0.0.1:1/nothing.jpg" },
      backoff: NO_WAIT
    ).call

    assert_not result.success?
    assert_match(/after #{ArtworkImporter::MAX_ATTEMPTS} attempts/, result.error)
  end

  test "an artwork arrives unreviewed unless the payload says otherwise" do
    assert_not import(title: "Fresh", collection: "Wikimedia canon").artwork.reviewed?
    assert import(title: "Vetted", collection: "Wikimedia canon", reviewed: true).artwork.reviewed?
  end

  private
    def import(attributes)
      ArtworkImporter.new(attributes, io: file_fixture("landscape.jpg").open).call
    end
end
