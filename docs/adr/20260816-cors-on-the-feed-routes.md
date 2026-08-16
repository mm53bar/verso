# 20260816 — CORS on the feed routes only, and `*` is the right value

## Context

The kiosk that consumes verso's feed is a browser showing a dashboard served from a loopback origin
on the device itself. A kiosk app commonly proxies the dashboard locally so the browser treats a
plain-HTTP page as a secure context and grants microphone access. The port belongs to whichever
kiosk app is installed.

So the page fetching `current.json` is on a different origin from verso, and **Rails sends no
`Access-Control-Allow-Origin` header by default.** The failure mode is quiet: the fetch rejects,
the script falls back to whatever wallpaper it already had, and nothing looks broken. The server it
replaces sends `Access-Control-Allow-Origin: *` for exactly this reason, and its documentation
flags the header as load-bearing.

The requirement is narrower than it first appears. Images used as CSS backgrounds need no CORS at
all. Because verso owns the rotation, there is no client write and therefore no preflight. A plain
`GET` policy on the JSON feed routes is the whole requirement.

## Decision

The read-only JSON feed routes send `Access-Control-Allow-Origin: *`. Nothing else in the app sends
any CORS header.

No gem. The header is set by a `before_action` on the feed controller — one line for one header on
one family of routes does not justify a dependency and its middleware.

## Consequences

- A kiosk needs no configuration, and neither does any other consumer we might add.
- **Scoping matters more than the value.** The ingestion endpoint deliberately gets no CORS header.
  A JSON `POST` from a browser triggers a preflight, and with no CORS headers on that route the
  preflight fails, so a page on another origin cannot drive verso's write path even though the app
  has no authentication. Applying CORS app-wide would throw that away for no benefit.
- The feed's contents are readable by any page a household device visits. What leaks is which
  picture is on a wall. This is acceptable.
- If verso ever grows per-person state or a genuine secret in the feed, `*` stops being
  appropriate, and that is the trigger to revisit — not before.

## Alternatives considered

- **Echo back an allowlisted `Origin`, with loopback allowed by default and named origins from an
  env var** — mirroring how the sibling recipe app handles CSP `frame-ancestors`. Rejected, and
  worth being explicit about why, because copying that shape looks like consistency.

  `frame-ancestors` accepts a wildcard pattern, so `http://127.0.0.1:*` is a policy the browser
  evaluates. `Access-Control-Allow-Origin` does not: it takes exactly one origin or `*`. Matching
  loopback therefore means reading the request's `Origin`, testing it against a pattern, echoing it
  back, and remembering `Vary: Origin` or the cache will serve one client's header to another. That
  is real machinery, and it is reflective — it grants the origin because the origin asked. For
  public read-only data that is `*` with extra steps and one more way to be wrong.

  The two ADRs answer different questions about different headers. `frame-ancestors` is a trust
  relationship — which origins may *embed* this app. CORS here is only "may script read this public
  JSON", and the honest answer is yes, anyone.
- **`rack-cors`.** Rejected: a gem, an initializer and a middleware for a single static header on a
  handful of routes.
- **Handle it at the reverse proxy.** Rejected: the proxy fronts several apps, the header is the
  application's to send, and a proxy-level override is invisible to anyone reading this repo. It
  also would not apply when a client reaches the app directly.
