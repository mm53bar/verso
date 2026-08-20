# 20260819 — A clock for the rotation, not an interval

Amends the cadence half of [20260816 — verso owns the
rotation](20260816-verso-owns-the-rotation.md). The one rotation of [20260817 —
One rotation across screens](20260817-one-rotation-two-shapes.md) **stands
unchanged**: both screens still show the same picture at the same time. Only the
clock moved.

## Context

Delivering an artwork to a Samsung Frame does not quietly replace a picture. The
upload switches the television into art mode, so it takes the set away from
whoever is watching it. With the rotation running hourly, that happened **every
hour, all evening**. The television was interrupting a show to show a painting.

Nothing about the rotation was wrong; the cadence was. Screens that stand in for
hanging pictures are looked at over a day, not over an hour, and the one screen
among them that is also a television is watched at particular hours. So the
requirement is not "how often" but "**when**" — and `cycle_seconds` cannot express
that. It measures forward from the last change, so a daily interval lands wherever
the previous one finished. The rotation job ticks once a minute, so each change
lands a little late and the next deadline is counted from there. The error
compounds, and a rotation asked for at 3am walks into the afternoon over a year,
which is precisely the collision it was meant to end.

## Decision

**A `Display` may hold `rotate_at`, a time of day, and a screen holding one
changes once a day at that time.** `cycle_seconds` still means what it always
meant for screens without one.

The anchor is recomputed from the wall clock on every tick — `due?` asks whether
`current_since` predates today's anchor — so it cannot drift, and it
self-corrects. If verso is down at 3am and back at 9am, the screen changes at 9am
rather than skipping the day. `1.day` arithmetic on a `TimeWithZone` handles the
two days a year that are not 86400 seconds long.

**The whole rotation runs on it: `rotate_at: "03:00"` on the kiosk, which leads.**
Every screen in the house changes at 3am and they go on showing the same picture,
so the ⓘ button still describes what is on the television and the eligibility
interlock still holds at 214 shared artworks. Nothing about the one-rotation
design is weakened; a house-wide cadence is exactly the kind of thing it exists to
make changeable in one place.

**The schedule belongs to the leader, and a follower's is left nil.** A follower
has no schedule of its own — `due?` returns false for one before it looks at
anything else. A `rotate_at` sitting on a follower would do nothing at all until
the day somebody stopped it following, and then silently govern. That is the same
shape as the bug `schedule_params` guards against when switching a screen back to
an interval, and both are why the unused half is cleared rather than left behind.

**The schedule is editable at `/settings`, not in `db/seeds.rb`.** Two reasons.
"What time does the art change" is exactly the sort of thing worth trying against
the actual household rather than reasoning about, and each attempt was otherwise a
deploy. And a schedule the seeds own is a schedule the seeds silently restore —
`max_crop_fraction` is the standing example of that trap, and it cost a review. So
`cycle_seconds`, `rotate_at` and `follows_display` are now assigned by the seeds
**only when the row is created**.

There is no `Setting` model, unlike tsundoku's. Every setting here is a fact about
a screen, and `Display` already owns those columns; a settings row holding a
schedule would be a second place to look for one.

## Consequences

**A round now takes 214 days instead of 214 hours.** At one artwork a day, the
collection is a year's worth of rotation rather than nine days of it, and the
coverage guarantee — every eligible piece shown before any repeats — stretches to
match. Weighting still works the same way; the cartoons at 2 are still about 13%
of a round, they just arrive one a week rather than one every seven hours. Whether
a picture a day is too slow for the kiosk, which is a dashboard background rather
than a hanging picture, is a judgement only the wall can make. Splitting the two
screens onto separate clocks is one form change away, and the cost of doing it is
written down below.

**The collision is reduced, not proven gone.** Home Assistant re-checks the
television every 15 minutes and retries an upload that failed, keyed on
`input_text.frame_uploaded_artwork` — deliberately, so a failed upload does not
wait for the next artwork. If the 3am upload fails, a retry can still land in the
evening. That is now the remaining path to an interruption and it lives in the
Home Assistant package, not here.

**`seconds_remaining` in the feed is computed from whichever schedule governs.** A
follower reported its own `cycle_seconds` before this, which was a number nothing
acted on; it now reports its leader's. So the television's feed counts down to
3am, which is what the voice countdown reads.

## Alternatives considered

**Have Home Assistant hold the upload until the television is off.**
`sensor.frame_display_mode` already knows. Rejected by Mike outright: it makes the
delivery path conditional on a device state that has to be read correctly every
time, to preserve an hourly cadence nobody asked for. Once a day overnight is not
a workaround for the interruption, it is the schedule the rotation should have had.

**`cycle_seconds: 86400`.** One column, no migration, and wrong for the reason in
the Context: it drifts, and where it drifts to is the evening.

**Leave the kiosk hourly and give only the television a daily clock.** Built first,
and wrong. It requires cutting the follow, because a follower cannot keep its own
schedule — and cutting the follow is what the ⓘ button is built on. The two screens
stop showing the same picture, "notice a painting on the television, read about it
on the kiosk" stops working, and each screen's rotation widens to whatever it can
render on its own (the kiosk from 214 to 276). That is a lot of the project's point
traded away for a faster wallpaper on the smaller screen.

**A recurring Solid Queue job per screen, with the cron expression in
`config/recurring.yml`.** Puts the schedule in the repo, which is the opposite of
what is wanted here, and `RotateDisplaysJob` is one job over one table precisely
so a third screen is a row rather than a deploy.
