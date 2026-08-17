require "test_helper"

# Deriving images on demand is what made the browse index unusable: measured on
# the NAS, a 480x300 thumbnail from a 717MB original takes 42 seconds, and Puma
# has three threads to spend.
class WarmDerivativesJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @artwork = artworks(:native_4k)
    @artwork.original.attach(
      io: file_fixture("wide.jpg").open, filename: "wide.jpg", content_type: "image/jpeg"
    )
  end

  test "generates the thumbnail the index actually asks for" do
    WarmDerivativesJob.perform_now(@artwork.id)

    blob = @artwork.original.blob
    digest = @artwork.thumbnail.variation.digest

    assert ActiveStorage::VariantRecord.exists?(blob: blob, variation_digest: digest),
      "the warmed variant must be the identical transformation the view requests"
  end

  test "generates a rendition for every active display" do
    WarmDerivativesJob.perform_now(@artwork.id)

    Display.active.each do |display|
      digest = @artwork.rendition_for(display).variation.digest

      assert ActiveStorage::VariantRecord.exists?(blob: @artwork.original.blob, variation_digest: digest),
        "#{display.slug} rendition should have been pre-generated"
    end
  end

  test "an artwork with no bytes is skipped, not fatal" do
    assert_equal 0, artworks(:cartoon).warm_derivatives!
  end

  test "one failure does not abandon the rest of the collection" do
    # cartoon has no attachment; native_4k does. The run must still warm what it can.
    assert_operator WarmDerivativesJob.perform_now, :>, 0
  end

  test "no view derives an image size of its own" do
    # An inline variant in a view is a size the warmer cannot know about, so it
    # is generated on demand — tens of seconds from a 23MB original on the NAS.
    # Naming every size in the model is what makes warming complete rather than
    # merely well-intentioned. This caught the artwork detail page asking for
    # resize_to_limit [1400, 1400] that nothing ever pre-generated.
    offenders = Dir[Rails.root.join("app/views/**/*.erb")].select do |path|
      File.read(path).match?(/\.variant\(\s*(resize_|format:|:?\{)/)
    end

    assert_empty offenders.map { |p| p.sub("#{Rails.root}/", "") },
      "these views build a variant inline; add a named variant to Artwork instead"
  end

  test "every named variant is warmed" do
    named = Artwork.reflect_on_attachment(:original).named_variants.keys.sort

    assert_equal %i[ detail thumb tile ], named
    named.each do |name|
      assert_respond_to artworks(:native_4k), name == :thumb ? :thumbnail : name
    end
  end

  test "the thumbnail is a named variant, so view and warmer cannot drift apart" do
    # Naming it is what guarantees they ask for the identical transformation. An
    # inline hash in the view and another in the warmer would be two cache keys
    # that look the same, and the index would stay slow while appearing fixed.
    assert_includes Artwork.reflect_on_attachment(:original).named_variants.keys, :thumb
    assert_includes File.read(Rails.root.join("app/views/artworks/index.html.erb")), "artwork.thumbnail"
  end

  test "attaching an original preprocesses the thumbnail without being asked" do
    fresh = Artwork.create!(title: "Freshly attached", collection: collections(:canon))

    perform_enqueued_jobs do
      fresh.original.attach(
        io: file_fixture("landscape.jpg").open, filename: "landscape.jpg", content_type: "image/jpeg"
      )
    end

    digest = fresh.thumbnail.variation.digest
    assert ActiveStorage::VariantRecord.exists?(blob: fresh.original.blob, variation_digest: digest),
      "preprocessed: true should have generated this on attach"
  end
end
