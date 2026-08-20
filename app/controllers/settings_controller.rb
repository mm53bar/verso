# Operator settings: the things about a running verso that a person changes
# without a deploy.
#
# There is no `Setting` singleton here, unlike tsundoku's. Everything editable so
# far is a fact about a *screen* — when it changes, and whether it mirrors
# another — and Display already owns those columns. A settings row holding a
# schedule would be a second place to look for one.
#
# Read-only, like the rest of the browse UI. The saves post to DisplaysController,
# which is where the writes that change a wall already live.
class SettingsController < ApplicationController
  def show
    @displays = Display.includes(:current_artwork, :follows_display).order(:name)

    # What each screen would be allowed to show, and what it can show on its own.
    # The two differ only while one screen follows another, and the gap is the
    # cost of that arrangement: a leader may only pick what its followers can
    # also render. Shown here because it is the surprise when a screen stops
    # following — the other one's rotation quietly widens.
    @eligible = @displays.to_h { |display| [ display.id, display.eligible_artworks.count ] }
    @own_eligible = @displays.to_h { |display| [ display.id, display.own_eligible_artworks.count ] }
  end
end
