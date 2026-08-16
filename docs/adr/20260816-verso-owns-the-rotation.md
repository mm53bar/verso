# 20260816 — verso owns the rotation, clients are dumb

## Context

verso replaces a plain nginx container that served a directory of images with a JSON autoindex.
Rotation lived on the client: injected JavaScript on a kiosk browser fetched the listing, shuffled
it, kept a cursor in `localStorage` keyed on a signature of the image set, and re-fetched every six
hours. A second consumer — a cron job that uploads art to a TV — did its own thing entirely,
picking a random file out of a different directory.

Two consumers, two unrelated selection mechanisms, and no component anywhere that could answer
"what is on that screen right now". The metadata problem is downstream of the same gap: a wallpaper
was a filename, so there was nothing to attach a title or an artist to.

Client-side rotation also can't express the things we want:

- **Weighting.** A small sub-collection of eight images went from appearing every eighth image to
  every nineteenth when the collection grew. A uniform random pick over a directory has no knob.
- **Coverage.** Re-shuffling on a timer makes rotation effectively random *with* replacement, so
  some images go unseen for weeks while others repeat.
- **Different screens.** Two displays with different aspect ratios and different cadences have
  nothing in common under a directory listing but the directory.

## Decision

verso decides what is displayed, on what schedule, on every screen. A client's only job is to ask
what to show and show it.

`Display` is a first-class model — one row per screen — holding the target dimensions, the cycle
length, the delivery transport, and a cursor (`current_artwork_id`, `current_since`,
`next_artwork_id`). One recurring job ticks every `Display`: if the cycle has elapsed, advance the
cursor and record a `DisplayEvent`. Both screens, one code path.

Clients get `GET /displays/:slug/current.json` and nothing else. Delivery differs by what the
client is — a browser polls HTTP because it has no other option; a cron script reads a file because
that is easiest — but the *decision* is verso's in both cases. Delivery is a transport detail, not
a second selection mechanism.

## Consequences

- **"What is on screen right now" is free and authoritative.** No POST back from the kiosk, no
  write endpoint, no CORS preflight, no question of whether to trust a client's self-report. The
  story feature and the voice query both need this, and both now start from solid ground rather
  than having to solve it first.
- **The injected kiosk script goes from roughly 70 lines to roughly 10.** The shuffle, the cursor,
  the `localStorage` persistence and the periodic re-fetch all delete outright — the persistence
  existed only so a client-side random choice would survive a reload, and asking the server twice
  returns the same answer. What survives is the idle guard (don't swap while someone is looking at
  it — the server cannot know that), the visibility guard, and preloading the next image.
- **The rotation clock moves off-device.** If verso is down, a screen keeps showing its last image
  and stops advancing. That is graceful and probably invisible for hours, and the kiosk's existing
  CSS fallback still covers a cold start with no verso at all. Accepted.
- Polling every 60 seconds is about 1400 requests a day from one device. That is nothing.
- History comes for free, because the job that advances the cursor is the natural place to record
  an event. "What was showing last Tuesday" becomes answerable, and a future "don't repeat anything
  from the last N" has the data it needs already.
- The cron job that drives the TV must have its schedule loosened to at least the display's cycle
  length. It currently runs weekly; a display cycling daily whose consumer only looks weekly still
  changes weekly, and it will look like verso is broken.

## Alternatives considered

- **Keep rotation on the device and have verso serve only metadata.** This was the earlier draft's
  position, on the grounds that the injected script's behaviour was hard-won. Rejected: most of
  that hard-won behaviour is scaffolding around client-side random choice and deletes rather than
  ports. It also leaves "what is on screen" unanswerable, which blocks the feature that motivates
  the app.
- **Have the client report back what it chose.** Rejected: strictly more machinery than choosing
  server-side — a write endpoint, a preflight, and a trust question — to reach a worse version of
  the same place.
- **Let each display type keep its own mechanism and have verso only own the images.** Rejected:
  this is the status quo's actual defect. Weighting, coverage and history would each have to be
  implemented twice, in two languages.
