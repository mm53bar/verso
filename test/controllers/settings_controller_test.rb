require "test_helper"

# The schedule is the one piece of configuration a person changes while looking
# at the wall it affects, so it is editable in the app rather than in
# db/seeds.rb. Same shape as the other writes here: a plain same-origin form post.
class SettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @kiosk = displays(:kiosk)
    @television = displays(:television)
  end

  test "the settings page names every screen and its schedule" do
    @television.update!(rotate_at: "03:00")

    get settings_path

    assert_response :success
    assert_select "h2", text: /Television/
    assert_match "once a day at 03:00", response.body
    assert_match Time.zone.name, response.body,
      "3am is meaningless without the zone it is 3am in"
  end

  # A form whose field names the controller does not read fails silently: the
  # page looks right, the save reports success and nothing changes.
  test "the form posts the names the controller reads" do
    @television.update!(rotate_at: "03:00")

    get settings_path

    assert_select "form[action=?][method=?]", display_schedule_path(@television.slug), "post"
    assert_select "input[name=?][value=?][checked]", "display[schedule_kind]", "daily"
    assert_select "select[name=?]", "display[cycle_seconds]"
    assert_select "input[name=?][value=?]", "display[rotate_at]", "03:00"
    assert_select "select[name=?]", "display[follows_display_id]"
  end

  test "switching a screen to a daily time of day" do
    patch display_schedule_path(@television.slug), headers: BROWSER, params: {
      display: { schedule_kind: "daily", rotate_at: "03:00",
                 cycle_seconds: @television.cycle_seconds, follows_display_id: "" }
    }

    assert_redirected_to settings_path
    assert_equal "03:00", @television.reload.rotate_at
    assert @television.daily?
  end

  test "switching back to an interval clears the time of day" do
    @television.update!(rotate_at: "03:00")

    patch display_schedule_path(@television.slug), headers: BROWSER, params: {
      display: { schedule_kind: "interval", rotate_at: "03:00",
                 cycle_seconds: 1.hour.to_i, follows_display_id: "" }
    }

    assert_nil @television.reload.rotate_at,
      "a left-behind rotate_at would go on overruling the interval just chosen"
    assert_equal 1.hour.to_i, @television.cycle_seconds
  end

  test "a screen can be told to stop mirroring another, and to start again" do
    @television.update!(follows_display: @kiosk)

    patch display_schedule_path(@television.slug), headers: BROWSER, params: {
      display: { schedule_kind: "daily", rotate_at: "03:00",
                 cycle_seconds: 1.day.to_i, follows_display_id: "" }
    }

    assert_nil @television.reload.follows_display_id

    patch display_schedule_path(@television.slug), headers: BROWSER, params: {
      display: { schedule_kind: "interval", cycle_seconds: 1.hour.to_i,
                 follows_display_id: @kiosk.id }
    }

    assert_equal @kiosk, @television.reload.follows_display
  end

  test "a time of day that is not one is refused and says so" do
    patch display_schedule_path(@television.slug), headers: BROWSER, params: {
      display: { schedule_kind: "daily", rotate_at: "3pm",
                 cycle_seconds: 1.day.to_i, follows_display_id: "" }
    }

    assert_redirected_to settings_path
    follow_redirect!
    assert_match "must be a time of day", response.body
    assert_nil @television.reload.rotate_at
  end

  test "the schedule is not writable from another origin" do
    patch display_schedule_path(@television.slug),
      headers: { "HTTP_ORIGIN" => "https://elsewhere.example" },
      params: { display: { schedule_kind: "daily", rotate_at: "03:00" } }

    assert_response :forbidden
    assert_nil @television.reload.rotate_at
  end
end
