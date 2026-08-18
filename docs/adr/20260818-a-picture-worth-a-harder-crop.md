# A picture worth a harder crop

## Context

The television accepts a 20% crop. That is a judgement about pictures in general,
and it refused two that Mike wanted anyway: The Night Watch is 1.23 against the
panel's 1.78 and needs 30.9%, and The Starry Night is 1.26 and needs 29.0%. He
looked at both on the wall at those crops and kept them — "an aggressive crop but
just such a great piece of art to have on the tv".

The obvious change was to raise the television's own figure to 31%. Measured on the
live collection, that takes the shared eligible set from **177 to 213** — it admits
about thirty six other artworks as a side effect, none of whose crops anybody had
looked at. The decision being made was about two paintings, not about a policy.

## Decision

**A nullable `artworks.max_crop_fraction`, used in place of the display's when
present.** `Display#acceptable_aspect_ratios(fraction = max_crop_fraction)` takes
the tolerance as an argument, and eligibility ORs the panel's window with the
artworks that individually reach their own.

Null means "use the screen's figure", which is every artwork but a handful.

## Consequences

The two paintings are in rotation and nothing else moved. A test asserts exactly
that: setting a tolerance on one artwork adds that artwork to the eligible set and
changes it in no other way.

The individual cases are resolved in Ruby and passed to the query as ids. The
arithmetic is per-row, so in SQL it would be a fragment computing bounds from a
column, and the set is a handful of artworks somebody decided about by hand.

**This is a second place where a crop is decided**, alongside `crop_focus_x/y`. They
are the same conversation from two directions — how much to lose, and which end to
lose it from — and a picture that needs one usually wants the other looked at too.
The Night Watch has both: a 32% tolerance and its whole crop taken off the top.

The column invites a slow drift toward hand-tuning the collection one artwork at a
time. Nothing forces it, and the honest signal is the count: if it ever holds more
than a dozen rows, the television's own figure is probably wrong and should be
raised instead.

## Alternatives considered

**Raise the television's `max_crop_fraction`.** The policy change described above.
Still the right move if the number of exceptions grows — see the count signal.

**`display_overrides`.** Already exists for per-artwork exceptions and would have
been fewer lines. Rejected on meaning: it says "show this regardless", and
suitability in this app is computed, never flagged. A tolerance keeps it computed —
the same arithmetic with a different number — and records *how much* crop was
accepted, which a boolean throws away.

**Per-display tolerance overrides**, a column on `display_overrides`. More precise
and unnecessary: which axis is cropped and by how much is already computed from the
two shapes, so one number per artwork gives the right answer on every screen.
