# Which half to keep

## Context

Cropping to fill discards from one axis and, until now, always took equal amounts
from both of its ends. That is the right default and it produced a bad answer for
a specific painting.

The Night Watch is 1.23 against the television's 1.78, so filling the panel throws
away 31% of its height. Centred, that is 482px off the top and 482px off the
bottom — and the two ends are not worth the same. The top of that picture is a
dark arch carrying almost nothing; the bottom is the floor, the foreground and the
feet. Mike looked at it on the wall and said the crop should come entirely off the
top, which is right and is not something the app could infer from the numbers.

Worth recording: libvips agrees. Asked for `attention` or `entropy`, its own smart
crops picked the same region as the human did (mean brightness 43.3 against a
centred 34.7 and a top-aligned 28.3). That is corroboration, not a reason to make
smart cropping the default — see below.

## Decision

**Two nullable columns on `Artwork`: `crop_focus_x` and `crop_focus_y`.**

`left`/`centre`/`right` and `top`/`centre`/`bottom`. `Artwork#crop_edge_for(display)`
picks whichever axis is actually being cropped — by comparing the two aspect
ratios — and translates the stored word into libvips' `:low` or `:high`.

**Two columns rather than one, because libvips takes one value.** Its `crop:`
option means "keep the low edge" or "keep the high edge" of whatever axis is being
cropped, so a single stored value cannot say both "keep the floor" and "keep the
left" — and this collection needs both, since the same artwork is cropped
vertically for the 16:9 television and horizontally for the 16:10 kiosk. Exactly
one axis is ever cropped for a given pair, so a preference per axis is
unambiguous, and the irrelevant one is ignored rather than misapplied.

**Stored as edges of the picture, not as libvips values.** `low` reads as the top
on one axis and the left on the other, which is correct and unreadable in a
database row. `CROP_EDGES` translates in one place.

## Consequences

**No existing rendition changes.** The transformation hash *is* the Active Storage
variant key, so `crop_edge_for` returns **nil** rather than `:centre` when there
is no preference, and `Display#variant_transformation` omits the options hash
entirely when passed nil. An explicit default would have re-keyed all ~570
renditions in the collection and regenerated every one to produce byte-identical
images. There is a test asserting exactly this, because it is the kind of
regression that costs an hour of NAS time and shows no symptom.

**The option goes inside `resize_to_fill`'s arguments, not beside it.** Every
top-level key in a transformation is applied as its own image operation, so a
stray `crop:` at the top level calls libvips' `crop` and dies with "you supplied 2
arguments, but operation needs 5". Found by running it.

Setting a focus on an artwork that already has renditions **does** re-key that
artwork's own variants, which is the point, but it means the new rendition is cold
and wants warming before a screen asks for it.

**AND NOTHING DOWNSTREAM NOTICES, WHICH THIS ADR ORIGINALLY FAILED TO SAY.**
Observed within the hour, on the wall: the crop was changed, the rendition was
regenerated, verso served the new bytes, and the television went on showing the old
picture. Two independent reasons, both following from the same broken invariant —
a rendition's bytes used to be a function of (artwork, display) and are now a
function of (artwork, display, crop focus):

1. **Home Assistant's upload is idempotent on the artwork id.** It stores what it
   last uploaded in `input_text.frame_uploaded_artwork` and skips when that equals
   the feed's current value. Both were `292`, so it correctly concluded the
   television was already right. That idempotence is load-bearing — it is what
   makes a failed upload retry for free — so the fix is not to remove it but to key
   it on something that changes when the bytes change.
2. **The rendition URL is served `Cache-Control: immutable, max-age=1 year`**,
   which is now a false promise. Any cache between verso and a screen may hold the
   old image indefinitely. On this occasion Thruster happened to have cached the
   new bytes rather than the old, which is luck rather than design.

The fix, not yet made: give the rendition URL a fingerprint of its own content
(`…/television.jpg?v=<checksum prefix>`), so that the URL changes exactly when the
bytes do — restoring the immutability claim instead of abandoning it — and have the
Home Assistant automation compare that URL rather than the artwork id.

This is per-artwork data and there is no rule to derive it from. That is a real
cost: 288 artworks, and any of them might deserve a look. Nothing forces the
issue, since the default remains a centred crop.

## Alternatives considered

**Make libvips' `attention` crop the default.** Tempting — it agreed with the
human judgement here, and it needs no data at all. Rejected for now on precedent:
the last heuristic in this project, a variance-based detector for photographs of
framed paintings, fixed ten cases and false-positived on low-variance snow scenes.
An automatic crop that is usually right is worse than a centred one that is always
predictable, because nobody knows which pictures it moved. It stays available as a
future `auto` value, cheaply, now that the plumbing exists.

**A focal point as x/y fractions**, as image CDNs do. More expressive, and the
extra expressiveness is unusable: libvips' `crop:` takes an edge, not a point, so
a focal point would have to be implemented with explicit `crop(x, y, w, h)`
arithmetic per display. Worth revisiting only if an artwork turns up that needs a
region rather than an edge.

**Per-display overrides of the crop.** `display_overrides` already exists for
membership. Rejected as unnecessary: which axis gets cropped is computed from the
shapes, so one pair of columns already gives the correct answer on every screen.
