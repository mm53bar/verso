# 20260817 — One rotation across screens, and matting instead of cropping

## Context

The two screens ran independent rotations. That was the obvious reading of
"verso owns the rotation for every screen", and it was wrong for how the house
actually uses them: you notice a painting on the television in one room, and the
button that explains it is on the kiosk in another. If the two are showing
different pictures, that button answers the wrong question.

Making them agree ran straight into geometry. The kiosk is 1920x1200 (1.60), the
television 3840x2160 (1.78). Both were cropping to fill, so a picture had to
survive *both* crops and beat *both* panels in both dimensions. Measured against
the real 154:

| | shared by both screens | Canadian collection within it |
|---|---|---|
| crop to fill, as built | 76 | 5 of 33 |
| crop harder (tolerance 0.32) | 102 | 25 |
| **matte, no crop, no upscale** | **117** | **28** |

The middle row is the trap. Widening the crop tolerance looks like a free win
until you notice what it does: a Group of Seven sketch panel is 1.235, and
cropping one to 16:9 discards about a third of the painting. That is not
showing the work, it is showing part of it — on the screen whose entire purpose
is pretending to be a hanging picture.

## Decision

**Render mode is per display.** `fill` crops to the panel's shape; `contain`
scales the whole picture in and mattes the remainder.

- The kiosk fills. It is a dashboard background with a clock over it, and matte
  bars there read as a broken image rather than as a mount.
- The television mattes. It is standing in for a framed painting, and a real
  Frame mattes non-16:9 art rather than cropping it.

**The size test follows from the mode, and this is where most of the gain is.**
Cropping to fill scales by the *larger* of the two ratios, so a source must beat
the panel in both dimensions. Scaling to fit scales by the *smaller*, so only
the limiting dimension has to — a tall picture needs the height, a wide one the
width. Aspect ratio stops constraining a matting display at all.

**One display may follow another.** A follower does not choose: it is told, in
the same transaction, and records its own `display_event` so each screen stays
independently answerable. It is never "due" on its own account, because letting
it advance on its own clock is exactly how the two would drift apart.

**A leader may only pick what all of its followers can render.** Otherwise it
would choose something a follower cannot show and the screens would silently
diverge — the failure this whole decision exists to prevent.

## Consequences

- The kiosk can no longer show 26 pieces it could show alone, all of them too
  small for the 4K panel in their limiting dimension. That is the price of the
  two screens agreeing, and it is much lower than the 67 that strict cropping
  would have cost.
- **Cadence is now shared and is one hour**, replacing 30 minutes on the kiosk
  and a day on the television. One clock for both, long enough that the
  television is not restless and short enough that the kitchen is not static.
- Cartoons small enough to fail the 4K test are deactivated rather than deleted,
  so higher-resolution replacements can be dropped in later. `active` is the
  curator's switch and this is exactly what it is for.
- Per-collection weighting only means anything on the leader now. Cartoons are
  no longer boosted: the count that justified boosting has dropped to the two
  large enough for the television, and they now appear in the living room too.
- `Artwork#rendition_for` asks the display how it wants to be fitted rather than
  hardcoding a crop, so a third screen with different manners costs a row.

## Alternatives considered

- **Widen the television's crop tolerance to 0.32.** Rejected above: 102 shared
  instead of 117, and it buys that by mutilating the composition of exactly the
  collection it appears to rescue.
- **Allow mild upscaling on the television** (1.5x would give 126 shared).
  Rejected for now: it trades visible softness on a large panel for two dozen
  more pieces, and matting already recovers most of them honestly. Worth
  revisiting only if the shared set feels thin in practice.
- **Let the screens diverge and have the story page ask which screen you mean.**
  Rejected: it pushes a question onto someone standing at a kiosk who just
  wants to know what the picture in the other room is.
- **Keep independent rotations and sync only "sometimes".** Rejected: a button
  that is usually right is worse than one that is always right, because there
  is no way to tell which case you are in.
