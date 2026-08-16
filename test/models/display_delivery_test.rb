require "test_helper"

class DisplayDeliveryTest < ActiveSupport::TestCase
  setup do
    @root = Pathname.new(Dir.mktmpdir("verso-delivery"))
    ENV["VERSO_DELIVERY_PATH"] = @root.to_s

    @television = displays(:television)
    @artwork = artworks(:native_4k)
    @artwork.original.attach(
      io: file_fixture("wide.jpg").open, filename: "wide.jpg", content_type: "image/jpeg"
    )
    @television.update!(current_artwork: @artwork, current_since: Time.current)
  end

  teardown do
    ENV.delete("VERSO_DELIVERY_PATH")
    FileUtils.remove_entry(@root)
  end

  test "writes the rendition where the consumer expects it" do
    assert @television.deliver!

    written = @root.join("television/current.jpg")
    assert_path_exists written
    assert_operator written.size, :>, 0
  end

  test "the delivered file is cropped to the panel, not the original shape" do
    @television.deliver!

    image = Vips::Image.new_from_file(@root.join("television/current.jpg").to_s)

    assert_equal @television.width, image.width
    assert_equal @television.height, image.height
  end

  test "the destination directory is created" do
    @television.update!(file_path: "deep/nested/path/current.jpg")

    assert @television.deliver!
    assert_path_exists @root.join("deep/nested/path/current.jpg")
  end

  test "no temporary file is left behind" do
    @television.deliver!

    leftovers = Dir.glob(@root.join("television/*"), File::FNM_DOTMATCH)
      .map { |p| File.basename(p) }
      .reject { |name| name.in?([ ".", "..", "current.jpg" ]) }

    assert_empty leftovers, "a temp file survived, so a reader could pick it up"
  end

  test "a replacement never leaves a partial file where the consumer reads" do
    @television.deliver!
    first = @root.join("television/current.jpg").binread

    @television.update!(current_artwork: attach_to(artworks(:sketch_panel), "landscape"))
    @television.deliver!
    second = @root.join("television/current.jpg").binread

    # Compare digests, not the bytes themselves: a failed byte comparison prints
    # both JPEGs into the test output.
    assert_not_equal Digest::MD5.hexdigest(first), Digest::MD5.hexdigest(second),
      "the second delivery should have replaced the first"
    # Both reads returned a complete JPEG rather than a truncated one, which is
    # what rename() into place buys: a reader on an unrelated schedule sees one
    # version or the other, never a half-written file.
    [ first, second ].each do |bytes|
      assert_equal "\xFF\xD8".b, bytes[0, 2], "not a JPEG header"
      assert_equal "\xFF\xD9".b, bytes[-2, 2], "truncated JPEG"
    end
  end

  test "an http display delivers nothing to disk" do
    displays(:kiosk).update!(current_artwork: @artwork, current_since: Time.current)

    assert_not displays(:kiosk).deliver!
    assert_empty @root.children
  end

  test "a display with no current artwork delivers nothing" do
    @television.update!(current_artwork: nil)

    assert_not @television.deliver!
  end

  private
    def attach_to(artwork, fixture)
      artwork.original.attach(
        io: file_fixture("#{fixture}.jpg").open, filename: "#{fixture}.jpg", content_type: "image/jpeg"
      )
      artwork
    end
end
