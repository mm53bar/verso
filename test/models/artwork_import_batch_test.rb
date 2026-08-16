require "test_helper"

class ArtworkImportBatchTest < ActiveSupport::TestCase
  # Records a call rather than sleeping, so pacing is asserted without waiting.
  class Sleeper
    attr_reader :waits
    def initialize = @waits = []
    def call(seconds) = @waits << seconds
  end

  setup do
    @sleeper = Sleeper.new
  end

  test "imports every record and reports the tally" do
    result = batch([
      local("First", "landscape"),
      local("Second", "wide")
    ]).call

    assert_predicate result, :success?
    assert_equal 2, result.imported
    assert_equal 2, result.total
    assert_equal 0, result.failed
  end

  test "local files are not paced" do
    batch([ local("First", "landscape"), local("Second", "wide") ]).call

    assert_empty @sleeper.waits, "there is nothing to be polite to on the local filesystem"
  end

  test "remote fetches are paced, but not before the first" do
    batch([ remote("One"), remote("Two"), remote("Three") ], delay: 10).call

    # Retry backoff shares this sleeper (20/40/80 at this delay), so count the
    # pacing gaps specifically: three fetches need two, and a leading one would
    # only waste ten seconds.
    assert_equal 2, @sleeper.waits.count(10)
  end

  test "a record already imported with bytes is skipped" do
    existing = artworks(:sketch_panel)
    existing.original.attach(
      io: file_fixture("landscape.jpg").open, filename: "landscape.jpg", content_type: "image/jpeg"
    )

    result = batch([ local("Anything", "wide").merge(slug: existing.slug) ]).call

    assert_equal 1, result.skipped
    assert_equal 0, result.imported
  end

  test "a record present but with no bytes is not skipped" do
    result = batch([ local("Anything", "wide").merge(slug: artworks(:sketch_panel).slug) ]).call

    assert_equal 0, result.skipped
    assert_equal 1, result.imported
    assert_predicate artworks(:sketch_panel).reload.original, :attached?
  end

  test "force re-imports even what is already there" do
    existing = artworks(:sketch_panel)
    existing.original.attach(
      io: file_fixture("landscape.jpg").open, filename: "landscape.jpg", content_type: "image/jpeg"
    )

    result = batch([ local("Anything", "wide").merge(slug: existing.slug) ], force: true).call

    assert_equal 0, result.skipped
    assert_equal 1, result.imported
    assert_equal 384, existing.reload.width, "the replacement bytes should have won"
  end

  test "an interrupted run resumes without redoing the finished work" do
    records = [ local("First", "landscape").merge(slug: "first"),
                local("Second", "wide").merge(slug: "second") ]

    batch([ records.first ]).call

    resumed = batch(records).call

    assert_equal 1, resumed.skipped
    assert_equal 1, resumed.imported
    assert_equal 2, Artwork.where(slug: %w[ first second ]).count
  end

  test "one bad record does not abandon the rest" do
    result = batch([
      local("Good", "landscape"),
      { title: "Bad", collection: "Wikimedia canon", image_path: "/no/such/file.jpg" },
      local("Also good", "wide")
    ]).call

    assert_not result.success?
    assert_equal 2, result.imported
    assert_equal 1, result.failed
    assert_equal 1, result.errors.length
    assert_match(/couldn't read/, result.errors.first)
  end

  test "progress is reported per record with its outcome" do
    seen = []
    ArtworkImportBatch.new(
      [ local("First", "landscape"), local("Second", "wide") ],
      sleeper: @sleeper, progress: ->(position, outcome, label, _artwork) { seen << [ position, outcome, label ] }
    ).call

    assert_equal [ [ "1/2", :imported, "First" ], [ "2/2", :imported, "Second" ] ], seen
  end

  test "retry backoff escalates from the configured pace" do
    # A hostile source gets a slower pace, so its retries must slow down too:
    # at a 5s pace the three retries wait 10, 20 and 40 rather than 2, 4 and 8.
    result = ArtworkImportBatch.new(
      [ { title: "Unreachable", collection: "Wikimedia canon",
          image_url: "http://127.0.0.1:1/nope.jpg" } ],
      delay: 5, sleeper: @sleeper
    ).call

    assert_equal [ 10, 20, 40 ], @sleeper.waits
    assert_equal 1, result.failed
    assert_match(/after #{ArtworkImporter::MAX_ATTEMPTS} attempts/, result.errors.first)
  end

  private
    def batch(records, **options)
      ArtworkImportBatch.new(records, sleeper: @sleeper, **options)
    end

    def local(title, fixture)
      { title: title, collection: "Wikimedia canon", image_path: file_fixture("#{fixture}.jpg").to_s }
    end

    def remote(title)
      { title: title, collection: "Wikimedia canon", image_url: "http://127.0.0.1:1/#{title}.jpg" }
    end
end
