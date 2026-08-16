require "test_helper"

class RotateDisplaysJobTest < ActiveSupport::TestCase
  setup do
    @root = Pathname.new(Dir.mktmpdir("verso-delivery"))
    ENV["VERSO_DELIVERY_PATH"] = @root.to_s

    Artwork.find_each do |artwork|
      next if artwork.original.attached?

      artwork.original.attach(
        io: file_fixture("wide.jpg").open, filename: "wide.jpg", content_type: "image/jpeg"
      )
    end
  end

  teardown do
    ENV.delete("VERSO_DELIVERY_PATH")
    FileUtils.remove_entry(@root)
  end

  test "advances every display that is due" do
    advanced = RotateDisplaysJob.perform_now

    assert_equal %w[ kiosk-panel television ].sort, advanced.sort
    assert_not_nil displays(:kiosk).reload.current_artwork
    assert_not_nil displays(:television).reload.current_artwork
  end

  test "leaves a display alone until its cycle has elapsed" do
    RotateDisplaysJob.perform_now
    showing = displays(:kiosk).reload.current_artwork

    RotateDisplaysJob.perform_now

    assert_equal showing, displays(:kiosk).reload.current_artwork
  end

  test "advances once the cycle has elapsed" do
    RotateDisplaysJob.perform_now
    kiosk = displays(:kiosk).reload
    showing = kiosk.current_artwork

    RotateDisplaysJob.perform_now(now: kiosk.current_since + kiosk.cycle_seconds)

    assert_not_equal showing, displays(:kiosk).reload.current_artwork
  end

  test "the two screens keep their own schedules" do
    RotateDisplaysJob.perform_now
    kiosk = displays(:kiosk).reload

    # Half an hour later the kiosk is due again; the television, on a day, is not.
    advanced = RotateDisplaysJob.perform_now(now: kiosk.current_since + 30.minutes)

    assert_equal [ "kiosk-panel" ], advanced
  end

  test "a file-delivery display gets its rendition written" do
    RotateDisplaysJob.perform_now

    assert_path_exists @root.join("television/current.jpg")
  end

  test "an inactive display is left alone" do
    displays(:kiosk).update!(active: false)

    assert_equal [ "television" ], RotateDisplaysJob.perform_now
  end

  test "a display with nothing eligible is skipped without blanking or raising" do
    Artwork.update_all(reviewed: false)

    assert_empty RotateDisplaysJob.perform_now
    assert_nil displays(:kiosk).reload.current_artwork
  end
end
