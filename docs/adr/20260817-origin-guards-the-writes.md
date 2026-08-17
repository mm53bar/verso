# 20260817 — The Origin header guards the writes, not a CSRF token

## Context

Pressing "Next picture" on the Echo Show returned 422, every time.

The log said `Can't verify CSRF token authenticity`, and the token *was* being
sent — the form rendered fine. What was missing was the session to compare it
against.

The kiosk story page exists to be framed by Home Assistant
([20260816](20260816-framed-by-home-assistant.md)). A form on that page posts back
to verso's own origin, so the *request* is same-origin, and that was the basis for
saying it needed no CORS. True, and irrelevant to cookies: the browsing context is
a cross-site iframe, which makes verso's session cookie a third-party cookie.
Rails sets it `SameSite=Lax`, browsers withhold it in that context, and with no
session there is nothing for the token to match.

**No test could have caught this.** `config.action_controller.allow_forgery_protection`
is `false` in the test environment, so the guard being broken is invisible until a
real browser meets it.

## Decision

Writes are guarded by the **Origin header** instead. `SameOriginWrite` skips
forgery protection on the three screen controls and refuses any write whose
`Origin` is not this app's own.

A CSRF token protects a *credential* from being used by another site. This app
deliberately has none ([20260816](20260816-no-auth-needed.md)), so the token was
never protecting an identity — only the nuisance of a stranger's page advancing
the art. The Origin header protects exactly that and survives the iframe: a
browser sets it on every form POST, and a hostile page cannot forge its own.

Reads are untouched. The feed is fetched cross-origin by the kiosk's own script
and is meant to be.

## Consequences

The wall works. A hostile page gets 403 rather than a rotation it does not own,
and the refusal is logged with the origin that tried.

A non-browser client — curl, a script — can no longer POST to these routes without
setting Origin. That is a real change, and acceptable: these three routes exist for
buttons. Anything automating verso should use the rotation, which is the app's own
job, or `bin/rails` inside the container.

## Alternatives considered

**`SameSite=None; Secure` on the session cookie.** Keeps the token working and is
the textbook answer for deliberate cross-site embedding. Rejected on two counts:
it requires the cookie to be accepted as a third party, which an Android WebView
may refuse outright and Chrome is phasing out generally; and a `Secure` cookie is
not sent over the plain-http LAN address at all, so the browse UI's own buttons
would break there instead. Trading one broken surface for another.

**Turn forgery protection off and add nothing.** Simplest, and it would work. It
also leaves nothing at all between a page on the internet and the screens, which
is the thing [the CORS ADR](20260816-cors-on-the-feed-routes.md) went out of its
way to preserve. The Origin check costs four lines and keeps that property.

**Make the buttons GET links.** No. A prefetcher would advance the rotation, and
some do it on hover.
