# 20260816 — Every filesystem path is configuration

## Context

verso touches the filesystem in three places: Active Storage's blob tree, the
directory `ArtworkExporter` writes the collection into, and the file a
`file`-delivery display's rendition is written to for another process to pick up.

The original brief named concrete paths for two of these, drawn from the NAS this
app was designed against. That is fine for one deployment and wrong for a public
repo — anyone else running verso lays their disks out their own way, and a path
written into a model is one they cannot change without a fork.

There is a second, independent reason, and it is the sharper one. verso has no
authentication (`20260816-no-auth-needed.md`). A display's write target is a
column in a table anyone who can reach the app may edit. If that column held an
absolute path, then "which file does verso overwrite with a JPEG" would be
attacker-controlled, bounded only by what the process can write — inside a
container that still includes the app's own config and database.

## Decision

**No filesystem path appears as a literal anywhere in the application.** Three
roots are defined in `config/application.rb` and read from the environment:

| helper | env var | default |
|---|---|---|
| `Verso.storage_root` | `VERSO_STORAGE_PATH` | `Rails.root/storage` |
| `Verso.export_root` | `VERSO_EXPORT_PATH` | `<storage_root>/export` |
| `Verso.delivery_root` | `VERSO_DELIVERY_PATH` | `<storage_root>/delivery` |

Each has a working default inside the app's own storage directory, so a fresh
clone runs with no configuration at all and a deployment overrides only the roots
it actually mounts elsewhere. `config/storage.yml` reads `Verso.storage_root`
rather than hardcoding the Disk service root.

**A `Display`'s `file_path` is stored relative to `delivery_root` and validated to
stay inside it.** `Pathname#join` replaces the root outright when handed an
absolute path, and `expand_path` resolves `..` lexically, so both escape attempts
land outside the root and are rejected by the same comparison.

Per-display paths therefore remain editable in the app — the operator picks
`television/current.jpg` — while the tree that name resolves inside is the
operator's to place.

## Consequences

- Someone else can run verso without editing Ruby. This is the point.
- The write target for a screen is settable in two independent places at the two
  levels each belongs to: the root is deployment configuration, the filename is
  application data.
- A container that wants verso to write somewhere a sibling process reads mounts
  that directory and sets `VERSO_DELIVERY_PATH` to it. No code changes, and the
  consumer keeps reading a fixed path.
- The containment check is lexical. It does not resolve symlinks, so an operator
  who deliberately symlinks something into the delivery root has still pointed
  verso at it. That is their decision to make, and defending against it would mean
  resolving the real path of a file that does not exist yet.
- `Rails.root/storage` as the default means the out-of-the-box layout keeps blobs,
  exports and delivery under one directory — the one already treated as the volume
  to persist.

## Alternatives considered

- **Absolute paths in the `Display` row, with no root.** Rejected on both counts:
  it hardcodes one machine's layout into the data, and it hands an unauthenticated
  write path an unbounded target.
- **A single `VERSO_DATA_PATH` with the three subdirectories fixed beneath it.**
  Simpler, and rejected only because the delivery directory is the one most likely
  to be a mount of somewhere entirely unrelated — it is shared with another
  process by definition, so it needs to move independently of the blobs.
- **Database-backed settings rather than env vars.** Rejected for the roots: a
  path the app needs before it can read its own database, in order to find the
  database, cannot come from the database. The per-display filename is data and
  does live in the database, which is the right split.
