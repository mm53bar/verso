# 20260816 — Let the household dashboard frame the story page

## Context

The kitchen wall screen shows a rotating artwork as the dashboard's background. The
point of verso's story feature is a button on that screen that answers "what am I
looking at" — artist, date, where it hangs, and eventually a written story.

The destination is a dashboard view that embeds a verso page in an iframe. That did
not work out of the box: Rails ships `X-Frame-Options: SAMEORIGIN` in
`config.action_dispatch.default_headers`, so the iframe renders an empty box. The
header has no multi-origin form — it is `DENY`, `SAMEORIGIN`, or nothing — and
browsers reject the combination of `X-Frame-Options` and CSP `frame-ancestors`, so
loosening it in place is not available. It has to go.

## Decision

Drop `X-Frame-Options` and set CSP `frame-ancestors` instead. The default policy
allows `'self'` plus loopback on any port; named origins come from a comma-separated
`VERSO_FRAME_ANCESTORS` env var, which most deployments will not need.

Loopback is in the default because of how kiosk browsers actually work. The kiosk app
serves the dashboard from a port on the device itself — a secure-context proxy, so a
plain-HTTP dashboard can still be granted microphone access — so the page framing
verso has a loopback origin whose port belongs to whichever kiosk app is installed.
That is a value nobody can predict and one that has nothing to do with how a human
reaches the dashboard. Requiring it to be configured means every kiosk deployment
starts with the same empty-box debugging session.

It also grants very little. A page can only present a loopback origin by already
running on the viewer's own machine, and an attacker who can serve HTTP from the
victim's localhost has better options than clickjacking an art label.

`frame-ancestors` is the only directive in the policy. `default_src` and `script_src`
would break the importmap and Turbo setup, and there is no untrusted content in verso
to defend against with them.

## Consequences

- Measured on the device (2026-08-16), the framing origin was loopback, so this
  household needs no `VERSO_FRAME_ANCESTORS` at all. The env var stays for reaching
  the same dashboard from a named host, such as a laptop.
- Getting the env var wrong fails the same way as having no header: an empty box, with
  no console-obvious cause.
- The framed view is `panel: true` with no chrome of its own, so there has to be a way
  back out. The dashboard's own navbar is included in that view, copying how the
  recipe app's view is built. The story page therefore needs no close control, though
  it still renders one when handed a `back` path.
- **A `back` path is only honoured when it is a same-site absolute path.** verso has
  no authentication, so an unchecked parameter reflected into a link would let anyone
  turn a household URL into a redirect anywhere. Schemes, hosts, protocol-relative
  URLs and backslash tricks are all refused, and a test enumerates them.
- The operational rule from the no-auth ADR is unchanged and matters slightly more:
  verso must not be deployed anywhere publicly reachable.

## Alternatives considered

- **Strip the header at the reverse proxy.** Rejected: the proxy fronts several apps,
  the header is the application's to send, and a proxy-level override is invisible to
  anyone reading this repo.
- **Scope the policy to the kiosk route only.** Rejected: the same screen will
  plausibly want another verso page next, and a per-controller policy is more
  machinery than the risk warrants on a LAN-only app with no login.
- **Reuse the browse UI instead of a dedicated kiosk page.** Rejected: the kiosk's CSS
  viewport is 854x534 at dpr 1.5, and type that reads fine on a laptop is unreadable
  across a kitchen. The story page is built for that viewport specifically.
