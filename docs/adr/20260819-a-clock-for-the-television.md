# 20260819 — A clock for the television, not an interval

Supersedes the single-rotation half of [20260817 — One rotation across screens,
and matting instead of cropping](20260817-one-rotation-two-shapes.md), and
overturns the last alternative rejected in [20260817 — Fit the screen, not the
art](20260817-fit-the-screen-not-the-art.md): the screens are now allowed to
disagree. The reason is not one either ADR had in front of it.

## Context

Delivering an artwork to a Samsung Frame does not quietly replace a picture. The
upload switches the television into art mode, so it takes the set away from
whoever is watching it. With both screens on one hourly rotation, that happened
**every hour, all evening**. The television was interrupting a show to show a
painting.

Nothing about the rotation was wrong; the cadence was. A television is watched at
particular hours, so the requirement is not "how often" but "**when**" — and
`cycle_seconds` cannot express that. It measures forward from the last change, so
a daily interval lands wherever the previous one finished. The rotation job ticks
once a minute, so each change lands a little late and the next deadline is
counted from there. The error compounds. A rotation asked for at 3am walks into
the afternoon over a year, which is precisely the collision it was meant to end.

## Decision

**A `Display` may hold `rotate_at`, a time of day, and a screen holding one
changes once a day at that time.** `cycle_seconds` still means what it always
meant for screens without one, which is every screen but the television.

The anchor is recomputed from the wall clock on every tick — `due?` asks whether
`current_since` predates today's anchor — so it cannot drift, and it
self-corrects. If verso is down at 3am and back at 9am, the screen changes at 9am
rather than skipping the day. `1.day` arithmetic on a `TimeWithZone` handles the
two days a year that are not 86400 seconds long.

**The television stops following the kiosk and rotates daily at 03:00.** One
rotation only ever worked because both screens shared a cadence, and they no
longer can. The kiosk stays hourly: it is a dashboard background, and nobody is
interrupted by it.

**The schedule is editable at `/settings`, not in `db/seeds.rb`.** Two reasons.
"What time does the art change" is exactly the sort of thing worth trying against
the actual household rather than reasoning about, and each attempt was otherwise a
deploy. And a schedule the seeds own is a schedule the seeds silently restore —
`max_crop_fraction` is the standing example of that trap, and it cost a review.
So `cycle_seconds`, `rotate_at` and `follows_display` are now assigned by the
seeds **only when the row is created**.

There is no `Setting` model, unlike tsundoku's. Every setting here is a fact about
a screen, and `Display` already owns those columns; a settings row holding a
schedule would be a second place to look for one.

## Consequences

**Each screen now picks from everything it can render, not from the intersection.**
A leader may only choose what its followers can also show, so while the television
followed, its 4K panel governed both: 214 of 289 artworks. Independent, the kiosk
clears **276** and the television **216**. The 62 pieces the kiosk gains are ones
the 4K panel is simply too large for. This is a widening, and a welcome one, but
it does mean the kiosk's rotation changed the day the television's schedule did.

**The ⓘ button now describes the kiosk only.** It frames `/kiosk/kiosk-panel`,
and while the screens agreed that answered for both. "Notice a painting on the
television, read about it on the kiosk" no longer works — that affordance was the
reason the two screens were locked together, and it is what the daily schedule
costs. The story page takes a display slug, so `/kiosk/television` already exists
and answers for the other screen; nothing currently frames it. Deciding what the
ⓘ should show is left open rather than guessed at.

**The collision is reduced, not proven gone.** Home Assistant re-checks the
television every 15 minutes and retries an upload that failed, keyed on
`input_text.frame_uploaded_artwork` — deliberately, so a failed upload does not
wait for the next artwork. If the 3am upload fails, a retry can still land in the
evening. That is now the remaining path to an interruption and it lives in the
Home Assistant package, not here.

**`seconds_remaining` in the feed is computed from whichever schedule governs.**
A follower reported its own `cycle_seconds` before this, which was a number
nothing acted on; it now reports its leader's.

## Alternatives considered

**Have Home Assistant hold the upload until the television is off.**
`sensor.frame_display_mode` already knows. Rejected by Mike outright: it makes the
delivery path conditional on a device state that has to be read correctly every
time, to preserve an hourly cadence nobody asked for on that screen. Once a day
overnight is not a workaround for the interruption, it is the schedule the screen
should have had.

**`cycle_seconds: 86400`.** One column, no migration, and wrong for the reason in
the Context: it drifts, and where it drifts to is the evening.

**Keep the television following, but let a follower adopt on its own schedule** —
at 3am it takes whatever the kiosk is showing. Preserves the eligibility interlock
and gives the two screens one hour a day in agreement. Rejected: it keeps the
kiosk narrowed to 214 to buy an overlap that is almost never the hour anyone is
looking, and "the picture is whatever the other screen happened to be showing at
3am" is a rule that has to be explained rather than read.

**A recurring Solid Queue job per screen, with the cron expression in
`config/recurring.yml`.** Puts the schedule in the repo, which is the opposite of
what is wanted here, and `RotateDisplaysJob` is one job over one table precisely
so a third screen is a row rather than a deploy.
