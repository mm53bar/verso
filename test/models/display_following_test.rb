require "test_helper"

# Two screens in two rooms showing the same picture, so that noticing a painting
# on one and reading about it on the other actually works.
class DisplayFollowingTest < ActiveSupport::TestCase
  setup do
    @kiosk = displays(:kiosk)
    @television = displays(:television)
    @television.update!(render_mode: "contain", follows_display: @kiosk)
    @kiosk.reload

    @kiosk.eligible_artworks.each do |artwork|
      next if artwork.original.attached?

      artwork.original.attach(
        io: file_fixture("wide.jpg").open, filename: "wide.jpg", content_type: "image/jpeg"
      )
    end
  end

  test "a leader may only pick what its followers can also render" do
    # legacy_crop suits the kiosk on its own but is too small for the 4K panel,
    # so once the television follows, the kiosk must stop choosing it.
    assert_includes @kiosk.own_eligible_artworks, artworks(:legacy_crop)
    assert_not @kiosk.eligible_artworks.include?(artworks(:legacy_crop))
  end

  test "advancing the leader moves the follower to the same artwork" do
    shown = @kiosk.advance!

    assert_equal shown, @television.reload.current_artwork
    assert_equal @kiosk.reload.next_artwork, @television.next_artwork
    assert_equal @kiosk.current_since.to_i, @television.current_since.to_i
  end

  test "the follower records its own history, so each screen stays answerable" do
    assert_difference -> { @television.display_events.count }, 1 do
      @kiosk.advance!
    end

    assert_equal @kiosk.reload.current_artwork, @television.display_events.recent.first.artwork
  end

  test "a follower never advances on its own schedule" do
    assert_not @television.due?, "a follower is never due; it moves when its leader does"
    assert_not @television.due?(now: 10.years.from_now)
  end

  test "the rotation job moves both screens together and delivers each" do
    root = Pathname.new(Dir.mktmpdir("verso-follow"))
    ENV["VERSO_DELIVERY_PATH"] = root.to_s

    advanced = RotateDisplaysJob.perform_now

    assert_equal %w[ kiosk-panel television ].sort, advanced.sort
    assert_equal @kiosk.reload.current_artwork, @television.reload.current_artwork
    assert_path_exists root.join("television/current.jpg")
  ensure
    ENV.delete("VERSO_DELIVERY_PATH")
    FileUtils.remove_entry(root) if root
  end

  test "each screen renders the shared artwork at its own size and mode" do
    @kiosk.advance!
    artwork = @kiosk.reload.current_artwork

    on_kiosk = Vips::Image.new_from_buffer(artwork.rendition_for(@kiosk).processed.download, "")
    on_tv    = Vips::Image.new_from_buffer(artwork.rendition_for(@television).processed.download, "")

    assert_equal [ 1920, 1200 ], [ on_kiosk.width, on_kiosk.height ]
    assert_equal [ 3840, 2160 ], [ on_tv.width, on_tv.height ]
  end

  test "a display cannot follow itself" do
    @kiosk.follows_display = @kiosk

    assert_not @kiosk.valid?
  end

  test "removing the leader leaves the follower standing rather than orphaned" do
    @kiosk.destroy!

    assert_nil @television.reload.follows_display_id
    assert_predicate @television, :valid?
  end
end
