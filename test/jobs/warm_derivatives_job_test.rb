require "test_helper"

# Deriving images on demand is what made the browse index unusable: measured on
# the NAS, a 480x300 thumbnail from a 717MB original takes 42 seconds, and Puma
# has three threads to spend.
class WarmDerivativesJobTest < ActiveSupport::TestCase
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

  test "the view and the warmer agree on the transformation" do
    # If these drift, the warmer caches images nobody requests and the index
    # stays slow while looking like it was fixed.
    assert_equal Artwork::THUMBNAIL, { resize_to_fill: [ 480, 300 ], format: :jpeg, saver: { quality: 80 } }
    assert_includes File.read(Rails.root.join("app/views/artworks/index.html.erb")), "artwork.thumbnail"
  end
end
