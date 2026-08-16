require "test_helper"

class ArtworkExporterTest < ActiveSupport::TestCase
  setup do
    @export = Pathname.new(Dir.mktmpdir("verso-export"))
  end

  teardown do
    FileUtils.remove_entry(@export)
  end

  test "originals are written under names a human can read" do
    attach(artworks(:sketch_panel), "landscape")

    export(scope: Artwork.where(id: artworks(:sketch_panel)))

    assert_path_exists @export.join("tom-thomson-a-sketch-panel.jpg")
  end

  test "a second run rewrites nothing when nothing changed" do
    attach(artworks(:sketch_panel), "landscape")
    scope = Artwork.where(id: artworks(:sketch_panel))

    first = export(scope: scope)
    assert_equal 1, first.written
    assert_equal 0, first.unchanged

    second = export(scope: scope)
    assert_equal 0, second.written
    assert_equal 1, second.unchanged
  end

  test "a replaced original is written again" do
    artwork = artworks(:sketch_panel)
    attach(artwork, "landscape")
    scope = Artwork.where(id: artwork)

    export(scope: scope)
    attach(artwork, "wide")

    assert_equal 1, export(scope: scope).written
  end

  test "an artwork with no original is reported, and the rest still export" do
    attach(artworks(:sketch_panel), "landscape")

    result = export(scope: Artwork.where(id: [ artworks(:sketch_panel), artworks(:cartoon) ]))

    assert_not result.success?
    assert_equal 1, result.errors.length
    assert_match(/no original attached/, result.errors.first)
    assert_equal 1, result.written
    assert_path_exists @export.join("tom-thomson-a-sketch-panel.jpg")
  end

  test "the manifest is ordered by slug so an unchanged export is byte-stable" do
    attach(artworks(:sketch_panel), "landscape")
    attach(artworks(:native_4k), "wide")
    scope = Artwork.where(id: [ artworks(:sketch_panel), artworks(:native_4k) ])

    export(scope: scope)
    first = @export.join(ArtworkExporter::MANIFEST).read

    export(scope: scope)
    second = @export.join(ArtworkExporter::MANIFEST).read

    slugs = JSON.parse(first)["artworks"].map { |a| a["slug"] }
    assert_equal slugs.sort, slugs

    # Only the timestamp may differ between two runs over unchanged data.
    assert_equal JSON.parse(first).except("exported_at"), JSON.parse(second).except("exported_at")
  end

  test "the manifest carries the metadata the filesystem cannot" do
    artwork = artworks(:sketch_panel)
    attach(artwork, "landscape")

    export(scope: Artwork.where(id: artwork))
    record = JSON.parse(@export.join(ArtworkExporter::MANIFEST).read)["artworks"].first

    assert_equal artwork.slug, record["slug"]
    assert_equal artwork.title, record["title"]
    assert_equal "Tom Thomson", record.dig("artist", "name")
    assert_equal "Canadian", record.dig("collection", "name")
    assert_equal artwork.original.blob.checksum, record["checksum"]
    assert_equal "image/jpeg", record["content_type"]
  end

  test "renditions are not exported, only originals" do
    attach(artworks(:sketch_panel), "landscape")
    export(scope: Artwork.where(id: artworks(:sketch_panel)))

    images = @export.children.map { |c| c.basename.to_s }.grep(/\.jpg\z/)

    assert_equal [ "tom-thomson-a-sketch-panel.jpg" ], images
  end

  test "the destination directory is created if it does not exist" do
    nested = @export.join("deeper/still")
    attach(artworks(:sketch_panel), "landscape")

    ArtworkExporter.new(path: nested, scope: Artwork.where(id: artworks(:sketch_panel))).call

    assert_path_exists nested.join(ArtworkExporter::MANIFEST)
  end

  private
    def attach(artwork, fixture)
      artwork.original.attach(
        io: file_fixture("#{fixture}.jpg").open,
        filename: "#{fixture}.jpg",
        content_type: "image/jpeg"
      )
      artwork
    end

    def export(scope:)
      ArtworkExporter.new(path: @export, scope: scope).call
    end
end
