require "test_helper"

class ArtworkExportJobTest < ActiveSupport::TestCase
  setup do
    @export = Pathname.new(Dir.mktmpdir("verso-export"))
  end

  teardown do
    FileUtils.remove_entry(@export)
  end

  test "writes the export and reports what it did" do
    artworks(:sketch_panel).original.attach(
      io: file_fixture("landscape.jpg").open, filename: "landscape.jpg", content_type: "image/jpeg"
    )

    result = ArtworkExportJob.perform_now(path: @export)

    assert_path_exists @export.join(ArtworkExporter::MANIFEST)
    assert_path_exists @export.join("tom-thomson-a-sketch-panel.jpg")
    assert_equal 1, result.written
  end

  test "an artwork with no original does not abort the run" do
    result = ArtworkExportJob.perform_now(path: @export)

    assert_not_predicate result, :success?
    assert_path_exists @export.join(ArtworkExporter::MANIFEST)
  end
end
