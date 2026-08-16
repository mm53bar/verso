require "test_helper"

# The load-bearing test for docs/adr/20260816-active-storage-with-round-trippable-export.md.
#
# Active Storage names blobs by random key, so its on-disk tree cannot be read
# by a human. The claim that the images are therefore still not trapped in verso
# rests entirely on the export being restorable — and an export nobody has ever
# restored from is a folder you believe in, not a backup. So: export a
# collection, destroy every record and every blob, rebuild from the directory
# alone, and assert nothing was lost.
class ExportRoundTripTest < ActiveSupport::TestCase
  setup do
    # This test asserts on the whole collection, so it needs to own the whole
    # collection. The shared fixtures carry artworks with no attachment, which
    # is a legitimate state everywhere except here. Transactional tests roll
    # this back.
    DisplayOverride.delete_all
    DisplayEvent.delete_all
    DisplayCollection.delete_all
    Artwork.delete_all
    Artist.delete_all
    Collection.delete_all

    @export = Pathname.new(Dir.mktmpdir("verso-export"))
  end

  teardown do
    FileUtils.remove_entry(@export)
  end

  test "a collection survives export, total destruction, and re-import" do
    before = seed_collection
    original_checksums = checksums_by_slug

    assert_predicate ArtworkExporter.new(path: @export).call, :success?

    destroy_everything
    assert_equal 0, Artwork.count
    assert_equal 0, Artist.count
    assert_equal 0, Collection.count
    assert_equal 0, ActiveStorage::Blob.count

    results = ArtworkImporter.from_export(@export)
    assert results.all?(&:success?), results.map(&:error).compact.to_sentence

    assert_equal before.length, Artwork.count
    assert_equal before.keys.sort, Artwork.pluck(:slug).sort
    assert_equal original_checksums, checksums_by_slug,
      "the bytes that came back are not the bytes that went in"

    before.each do |slug, attributes|
      restored = Artwork.find_by!(slug: slug)

      attributes.each do |field, value|
        actual = restored.public_send(field)

        if value.nil?
          assert_nil actual, "#{slug}.#{field} came back set when it went in empty"
        else
          assert_equal value, actual, "#{slug}.#{field} did not survive"
        end
      end
    end
  end

  test "artists and collections are rebuilt, not duplicated" do
    seed_collection
    ArtworkExporter.new(path: @export).call
    destroy_everything
    ArtworkImporter.from_export(@export)

    assert_equal [ "Lawren Harris", "Tom Thomson" ], Artist.order(:name).pluck(:name)
    assert_equal [ "Canadian", "Wikimedia canon" ], Collection.order(:name).pluck(:name)

    # Two works by the same artist must share one record — the whole reason
    # Artist exists rather than a string column on Artwork.
    assert_equal 2, Artist.find_by(name: "Tom Thomson").artworks.count
  end

  test "an artist's biography survives, written once and shared" do
    seed_collection
    ArtworkExporter.new(path: @export).call
    destroy_everything
    ArtworkImporter.from_export(@export)

    thomson = Artist.find_by!(name: "Tom Thomson")

    assert_equal 1877, thomson.birth_year
    assert_equal 1917, thomson.death_year
    assert_equal "Canadian", thomson.nationality
    assert_equal "Painted the Ontario near north.", thomson.bio
  end

  test "a piece with no artist round-trips as a piece with no artist" do
    seed_collection
    ArtworkExporter.new(path: @export).call
    destroy_everything
    ArtworkImporter.from_export(@export)

    assert_nil Artwork.find_by!(slug: "an-unattributed-cartoon").artist
  end

  test "re-importing over a live collection updates in place rather than duplicating" do
    seed_collection
    ArtworkExporter.new(path: @export).call

    assert_no_difference [ "Artwork.count", "Artist.count", "Collection.count" ] do
      ArtworkImporter.from_export(@export)
    end
  end

  test "the export directory is readable without verso" do
    seed_collection
    ArtworkExporter.new(path: @export).call

    names = @export.children.map { |child| child.basename.to_s }.sort

    assert_equal [
      "an-unattributed-cartoon.jpg",
      "lawren-harris-north-shore.jpg",
      "manifest.json",
      "tom-thomson-a-sketch.jpg",
      "tom-thomson-the-jack-pine.jpg"
    ], names

    manifest = JSON.parse(@export.join("manifest.json").read)

    assert_equal ArtworkExporter::VERSION, manifest["version"]
    assert_equal 4, manifest["count"]
    assert_equal 4, manifest["artworks"].length
    assert manifest["exported_at"].present?
  end

  private
    # Returns slug => the fields that must survive, so the assertion loop reads
    # as a specification rather than a pile of asserts.
    def seed_collection
      canon = Collection.create!(name: "Wikimedia canon", weight: 1, minimum_aspect_ratio: 1.3)
      canadian = Collection.create!(name: "Canadian", weight: 2, minimum_aspect_ratio: 1.235)

      thomson = Artist.create!(name: "Tom Thomson", birth_year: 1877, death_year: 1917,
                               nationality: "Canadian", bio: "Painted the Ontario near north.")
      harris = Artist.create!(name: "Lawren Harris", birth_year: 1885, death_year: 1970)

      attach = lambda do |artwork, file|
        artwork.original.attach(
          io: file_fixture("#{file}.jpg").open, filename: "#{file}.jpg", content_type: "image/jpeg"
        )
        artwork.record_dimensions!
        artwork
      end

      attach.call(Artwork.create!(
        title: "The Jack Pine", artist: thomson, collection: canadian,
        year_text: "1916–17", medium: "Oil on canvas",
        current_location: "A national gallery",
        blurb: "One or two plain sentences, because this one gets spoken aloud.",
        story: "The long form, for a screen rather than a speaker.",
        source: "Wikimedia Commons", source_file: "The Jack Pine.jpg",
        wikidata_qid: "Q1234567", license: "Public domain",
        credit_line: "Gift of an anonymous donor",
        reviewed: true, active: true, weight: 3
      ), "landscape")

      attach.call(Artwork.create!(title: "A Sketch", artist: thomson, collection: canadian,
                                  reviewed: true), "landscape")
      attach.call(Artwork.create!(title: "North Shore", artist: harris, collection: canon,
                                  reviewed: false, active: false), "wide")
      attach.call(Artwork.create!(title: "An unattributed cartoon", collection: canon,
                                  weight: 5), "wide")

      Artwork.all.index_with do |artwork|
        {
          title: artwork.title, year_text: artwork.year_text, blurb: artwork.blurb,
          story: artwork.story, medium: artwork.medium,
          current_location: artwork.current_location, source: artwork.source,
          source_file: artwork.source_file, wikidata_qid: artwork.wikidata_qid,
          license: artwork.license, credit_line: artwork.credit_line,
          active: artwork.active, reviewed: artwork.reviewed, weight: artwork.weight,
          width: artwork.width, height: artwork.height, aspect_ratio: artwork.aspect_ratio
        }
      end.transform_keys(&:slug)
    end

    def checksums_by_slug
      Artwork.includes(original_attachment: :blob).to_h do |artwork|
        [ artwork.slug, artwork.original.blob.checksum ]
      end
    end

    def destroy_everything
      Artwork.find_each { |artwork| artwork.original.purge }
      Artwork.destroy_all
      Artist.destroy_all
      Collection.destroy_all
    end
end
