# 20260817 — Fit the screen, not the art

> **Amended the same day: the window is 0.20, not 0.10.** The decision below
> stands — the television crops and its aspect window governs the shared
> rotation — but the number moved once cropping had been seen on the wall. 0.20
> had been rejected earlier on the strength of a *matte* at that tolerance, which
> is a different judgement: a fifth of the panel given to mount board looks like a
> small picture adrift, where a fifth cropped off a large painting reads as a
> tighter frame. Judged on *The Potato Eaters* at 1.414, the worst case the window
> admits, and accepted. The effect was 26 famous paintings already in the
> collection returning to rotation, plus four Group of Seven works, for the cost
> of a warm pass. The consequences section below describes the 0.10 world.

Supersedes the matting half of [20260817 — One rotation across screens, and
matting instead of cropping](20260817-one-rotation-two-shapes.md). The one
rotation stands; the matting does not.

## Context

The television was matting: the whole picture scaled to fit 3840x2160 and the
remainder filled with a colour. That decision was made on the reasoning that a
screen standing in for a framed painting should show the whole painting, and it
bought a lot of collection — 117 shared artworks against 76 for cropping, and the
Canadian collection went from 5 of 33 to 28.

Seen on the actual television, it does not work. Three findings, in order of how
much they mattered:

**The matte read as letterboxing, not as a mount.** It was `#111111`, near-black,
which was never a considered choice — the migration that added `render_mode`
explains the mode carefully and says nothing about the colour. White was tried
and was too bright. Cream at `#EDE7DA` was tried and looked like a mount, which
exposed the real problem rather than fixing it.

**`resize_and_pad` cannot produce a mount at all.** It fits the artwork to the
panel, so anything narrower than 16:9 meets the top and bottom edges exactly and
the colour appears only down the sides. A matte surrounds a picture. Getting a
border on four sides needs the artwork scaled into a smaller box first, which is
what `matte_inset` does. With that in place it genuinely looked like a mounted
picture — and a mounted picture on a 65 inch landscape screen still looked wrong,
because the mount was doing most of the work. A Group of Seven sketch panel at
1.232 lands with 731px of mount down each side against 130px top and bottom.

**Almost nothing in the collection is 16:9.** Measured against the 121 shared
artworks: 97 are narrower than the screen, and only 28 come within 10% of fitting.
The television is the outlier, not the art, and no amount of presentation fixes
that.

The premise the earlier ADR rested on also turns out to be false. It asserted
that "a real Frame mattes non-16:9 art rather than cropping it". The 13 pieces
bought for the Frame are all *exactly* 3840x2160, and comparing four of them
against the same paintings from Commons shows they were cropped to get there,
losing 15% to 26% of the picture. Samsung crops.

## Decision

**The television crops to fill, and the aspect window decides what it can show.**
`render_mode: fill`, `max_crop_fraction: 0.10`.

The house is optimising for how the wall looks, not for holding the whole
collection. A picture either fits the screen within 10% or it is not shown there.

**10% is the total loss, not the loss per edge.** `acceptable_aspect_ratios`
already computes `D*(1-f) .. D/(1-f)`, which at `f = 0.10` is 1.6 to 1.975, and
that is exactly "at most 10% of the picture discarded". Centred, so it is 5% off
each edge. Judged on *The Coronation of Napoleon* at 1.609, the worst case the
window admits: 4.8% off the top and the bottom of a crowded ceremonial scene is
not noticeable.

**Nothing is deleted or deactivated.** The line is drawn by the eligibility rule,
so an artwork outside the window simply stops being picked. Every original,
story and blurb stays, and widening the window or adding a differently shaped
screen brings them straight back. That matters because the excluded set is large.

**One rotation still governs.** Both screens continue to show the same artwork,
which means the television's window applies to the kiosk as well. That is a real
cost, paid deliberately: the ⓘ button explaining what is on the television is the
point of the project, and it only works if the two agree.

## Consequences

The shared set goes from **121 to 26**: 10 Frame, 9 canon, 7 cartoons, and
**none of the Canadian collection**. Every Thomson panel, all the Harris and
MacDonald, both Carrs. The sketch panel format that makes that collection
coherent is exactly what a 16:9 screen cannot take. This was accepted explicitly.

A round is 33 slots, about a day and a half, against five and a half days before.
Cartoons at weight 2 are 14 of those 33, roughly 42%, which is temporary: the
intent is to acquire art that fits by default rather than to reweight.

`contain` and the matte code stay. They are tested and they work, and a screen of
a different shape may want them. Nothing currently selects them.

## Alternatives considered

**Keep matting.** Rejected on sight, on the wall, twice — black looked like
letterboxing and cream looked like a small picture adrift on a large board.

**A more generous window.** 20% keeps 61 artworks but means 10% off each edge, and
*The Floor Scrapers* at 1.423 was judged too heavily mounted at that boundary.
30% keeps 104 and returns 11 Canadian works, but it cuts through one body of work
arbitrarily: *Falls, Montreal River* at 1.252 survives while *Autumn Birches* at
1.232 does not, and nobody can see a 1.6% difference in aspect ratio on a wall.

**Black bars for near misses and a matte beyond.** Two visual languages on one
screen with an arbitrary switch between them. Cropping removes the need: a
picture within 10% simply fills the screen.

**Let the screens disagree** — the television strict, the kiosk keeping its wider
set. This is the only option that preserves both the wall and the collection, and
it was rejected because it breaks the ⓘ.
