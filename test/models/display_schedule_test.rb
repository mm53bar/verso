require "test_helper"

# A screen that changes at a time of day rather than after an interval.
#
# The television is watched, so being interrupted is the complaint that produced
# this: delivering an artwork to a Frame TV switches it out of whatever is on
# screen and into art mode. The fix is a schedule that can say "3am", which an
# interval cannot.
class DisplayScheduleTest < ActiveSupport::TestCase
  setup do
    @television = displays(:television)
    @television.update!(follows_display: nil, rotate_at: "03:00")
  end

  test "a time of day is normalized however it arrives" do
    { "03:00" => "03:00", "3:00" => "03:00", "03:00:00" => "03:00",
      "23:45" => "23:45", "" => nil, nil => nil }.each do |given, expected|
      @television.rotate_at = given
      if expected.nil?
        assert_nil @television.rotate_at, "#{given.inspect} should normalize to nil"
      else
        assert_equal expected, @television.rotate_at, "#{given.inspect} should normalize"
      end
    end
  end

  test "something that is not a time of day is refused rather than coerced" do
    [ "24:00", "03:60", "3pm", "0300", "midnight" ].each do |given|
      @television.rotate_at = given
      assert_not @television.valid?, "#{given.inspect} should not be a legal rotate_at"
    end
  end

  test "not due before the day's anchor, due after it, and not twice" do
    travel_to Time.zone.parse("2026-09-01 03:00") do
      @television.update!(current_since: Time.current)
    end

    travel_to Time.zone.parse("2026-09-02 02:59") do
      assert_not @television.due?, "an evening's viewing must not be interrupted"
    end

    travel_to Time.zone.parse("2026-09-02 03:00") do
      assert @television.due?
    end

    travel_to Time.zone.parse("2026-09-02 03:01") do
      @television.update!(current_since: Time.current)
      assert_not @television.due?, "one change a day, not one a minute after 3am"
    end
  end

  test "the anchor does not drift, however late the tick that takes it" do
    # The job ticks once a minute, so a change always lands a little after the
    # anchor. Counting the next deadline from *that* is what walks a 3am rotation
    # into the evening over a year; the anchor is recomputed from the clock.
    travel_to Time.zone.parse("2026-09-01 03:00:47") do
      @television.update!(current_since: Time.current)
    end

    travel_to Time.zone.parse("2026-09-02 03:00:10") do
      assert @television.due?, "10 seconds past 3am is the second day's turn"
    end
  end

  test "a missed anchor is taken late rather than skipped" do
    travel_to Time.zone.parse("2026-09-01 03:00") do
      @television.update!(current_since: Time.current)
    end

    # verso was down at 3am and came back at 09:30.
    travel_to Time.zone.parse("2026-09-02 09:30") do
      assert @television.due?
      assert_equal Time.zone.parse("2026-09-02 03:00"), @television.last_rotation_anchor
    end
  end

  test "a screen that has never shown anything is due at once" do
    @television.update!(current_since: nil)

    travel_to Time.zone.parse("2026-09-02 14:00") do
      assert @television.due?
    end
  end

  test "an interval screen is untouched by any of this" do
    kiosk = displays(:kiosk)

    assert_not kiosk.daily?
    kiosk.update!(current_since: 31.minutes.ago)
    assert kiosk.due?

    kiosk.update!(current_since: 29.minutes.ago)
    assert_not kiosk.due?
  end

  test "a follower still has no schedule of its own" do
    @television.update!(follows_display: displays(:kiosk), current_since: 2.days.ago)

    travel_to Time.zone.parse("2026-09-02 04:00") do
      assert_not @television.due?, "a follower moves when its leader does, never alone"
    end
  end

  test "the clock a screen reports is the one that governs it" do
    kiosk = displays(:kiosk)

    assert_equal 1.day.to_i, @television.cadence_seconds
    assert_equal kiosk.cycle_seconds, kiosk.cadence_seconds

    @television.update!(follows_display: kiosk)
    assert_equal kiosk.cycle_seconds, @television.cadence_seconds,
      "a follower's own interval is a number nothing acts on"
  end

  test "seconds remaining counts down to the next anchor" do
    travel_to Time.zone.parse("2026-09-01 03:00") do
      @television.update!(current_since: Time.current)
    end

    travel_to Time.zone.parse("2026-09-01 21:00") do
      assert_equal 6.hours.to_i, @television.seconds_remaining
    end

    travel_to Time.zone.parse("2026-09-02 03:00") do
      assert_equal 0, @television.seconds_remaining, "overdue reads as none left"
    end
  end

  test "a daily screen still changes only once across a spring forward" do
    # Edmonton loses the 02:00 hour on 2027-03-14, so 01:59 MST and 03:00 MDT are
    # one minute of real time apart. 3am exists on both days; the question is
    # whether a day that is 23 hours long confuses the count.
    travel_to Time.zone.parse("2027-03-13 03:00") do
      @television.update!(current_since: Time.current)
    end

    travel_to Time.zone.parse("2027-03-14 01:59") do
      assert_not @television.due?
    end

    travel_to Time.zone.parse("2027-03-14 03:00") do
      assert @television.due?
    end
  end

  test "the schedule reads as a sentence" do
    assert_equal "once a day at 03:00", @television.schedule_description
    assert_equal "every 30 minutes", displays(:kiosk).schedule_description

    @television.update!(follows_display: displays(:kiosk))
    assert_equal "mirrors Kiosk panel", @television.schedule_description
  end
end
