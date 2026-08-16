# 20260816 — No authentication

## Context

verso holds a shared collection of art and drives the screens in one household. There is no
per-person state in it: an artwork's title, its story, and which picture is on the kitchen screen
belong to the house, not to a user. The deployment target resolves only on the private network
behind this household's reverse proxy, and there is no public exposure to defend against.

A sibling app in this household reached the same conclusion for the same reasons, and its
reasoning applies here without modification.

## Decision

verso ships with no authentication: no `User` model, no login flow, no proxy-header trust model.
Every request is treated as coming from a trusted household member. That includes the ingestion
endpoint — writes are made by an agent over the API, and the API is as open as the rest of the app.

## Consequences

- No `require_authentication`, no dev-login bypass, no user provisioning.
- **The app must never be deployed anywhere publicly reachable.** `compose.yaml`'s header comment
  says so explicitly. This is an operational responsibility; the app does not enforce it.
- The write path is unauthenticated, so anything that can reach verso on the network can add or
  change an artwork. On a household LAN this is the same trust boundary the read path already has.
  It is worth noting because a write path feels different from a read path even when the exposure
  is identical — the mitigation that matters is not deploying it publicly, not a token.
- CORS is scoped so a *browser* on another origin still cannot drive the write path
  (`20260816-cors-on-the-feed-routes.md`). That is not authentication and should not be mistaken
  for it; it only closes the drive-by case.
- Per-person state is the trigger to revisit this — a personal favourites list, say, or knowing who
  added a story. Not before.

## Alternatives considered

- **Trust forward-auth headers from the household's identity proxy,** as two older apps here do.
  Rejected: those apps show data that belongs to one signed-in person. verso has none, so this
  would add a trust boundary and a dev bypass for no protected asset.
- **Authenticate only the write path,** with a shared token for the ingesting agent. Rejected for
  now: it protects against an attacker who is already on the private network, which is not the
  threat model, and it adds a secret to distribute and rotate. Reconsider if verso is ever exposed
  beyond the LAN — but the correct response to that would be to stop exposing it.
