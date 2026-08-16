# 20260816 — Secrets come from env vars, not Rails encrypted credentials

## Context

This repo is public from its first commit. Rails' default encrypted-credentials workflow
(`config/credentials.yml.enc` plus `config/master.key`) commits an encrypted file and keeps the key
out of it — sound in principle, but it is one more thing every clone has to get right, and a
credentials file carried in a public repo becomes a shared secret across every fork the moment
anyone encrypts a real value into it by mistake.

verso needs exactly one secret to boot, `SECRET_KEY_BASE`, and has no third-party API credentials
at all.

## Decision

Runtime configuration and secrets are read from environment variables, set in `compose.yaml`.
Nothing in the app calls `Rails.application.credentials`.

`config/credentials.yml.enc` and `config/master.key` were **deleted from the generated scaffold in
the first commit** and are git-ignored. Rails 8.1 resolves `ENV["SECRET_KEY_BASE"]` before
consulting credentials, so this needs no code — only not shipping the file.

An operator who prefers the encrypted-credentials workflow can bring their own key and file
locally. Nothing prevents it; it is just not required to boot, and this repo will never ship one.

## Consequences

- `compose.yaml` must set `SECRET_KEY_BASE` explicitly. There is no fallback baked into the image,
  and the app will refuse to boot in production without it — which is the right failure.
- Cloning and running the repo needs no key material beyond that one variable.
- `compose.yaml` in this repo is a template carrying placeholders only. The real values live in the
  deployed copy, outside version control.
- Any future feature wanting a secret adds an env var read through `ENV.fetch`. If the value is
  really operator-editable runtime configuration rather than a secret, it belongs in the database
  instead.

## Alternatives considered

- **Rails encrypted credentials as the primary mechanism.** Rejected: heavier than the problem. For
  a public repo with one required secret, every clone would either generate its own credentials
  file or fall back to an env var anyway, so committing to env vars from the start is simpler and
  matches the other apps here.
