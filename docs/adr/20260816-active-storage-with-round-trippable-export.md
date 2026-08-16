# 20260816 — Active Storage for the bytes, with a round-trippable export

## Context

verso needs to hold a few hundred images and derive a rendition per display: one aspect ratio for
a 16:10 kiosk panel, another for a 16:9 television, from the same source picture. Two options were
real.

**Active Storage.** `has_one_attached :original`, renditions as variants through libvips, which is
already in the standard Rails 8 Dockerfile. The bytes live on disk under the Disk service, named by
a random blob key; the filenames, checksums and content types live in SQLite. The crop pipeline
moves into the app, where it belongs — today it is ImageMagick invocations in a throwaway script.

**A plain directory the app points at.** Bytes stay in a human-browsable folder and verso owns only
metadata. Keeps the folder readable, keeps the existing consumer working untouched, and costs the
derivation pipeline: something outside the app still has to produce every rendition, and safe path
resolution becomes the app's problem.

The deciding objection to Active Storage was not technical. It was that a tree of files named
`ab/cd/abcd1234…` is not something a human can recover art from. An operator who wants the pictures
back should not need a running Rails app and a matching SQLite file to get them.

That objection is fair, and it is also fixable, which is what this ADR is really about.

## Decision

Active Storage holds the bytes. **Originals are stored at full resolution**; every display-sized
image is a derived variant, never the stored artifact.

Alongside it, `ArtworkExporter` writes the collection back out in a form that needs no verso at
all:

```
export/
├── manifest.json                             ← every field of every record
├── tom-thomson-the-jack-pine.jpg             ← the original, full resolution
└── lawren-harris-north-shore-lake-superior.jpg
```

Originals only. Renditions are derivable by definition, and writing them would triple the export
for no recoverable information.

The export runs on a schedule, and it is idempotent: Active Storage already stores a checksum per
blob, so a run after the first copies only what changed.

**`ArtworkImporter` can read an export directory as a source, and a test asserts the round trip.**
Export then re-import must reproduce every record and every byte. This is the load-bearing part of
the decision — it is what makes "the images are not trapped in verso" a property the CI gate
verifies rather than a claim in a README. An export nobody has ever restored from is a folder you
believe in.

## Consequences

- One source of truth for the bytes, and the crop pipeline lives in the app under test instead of
  in a script that was thrown away after it ran.
- **SQLite and the blob tree are useless apart.** They must be backed up together, or via the
  export, which is precisely why the export exists.
- The image directory stops being browsable. The export directory is the answer, and it is better
  than the old folder was: human-readable names derived from artist and title rather than
  `art-a-bar-at-the-folies-berg-re-manet.jpg`, plus a manifest carrying metadata the filesystem
  could never hold.
- **Variants must be served through `rails_storage_proxy`,** not the default redirect route. The
  redirect costs an extra round trip on every image swap, cross-origin, on a weak device.
- Artwork URLs must be stable and must not embed a variant key, or regenerating a variant changes
  the URL and clients swap for no reason.
- Existing consumers that read a directory have to change. In practice this is one line in one
  script, because verso writes the rendition to a known path for file-delivery displays.
- The export is a good ingestion source in its own right — seeding a development machine from a
  production export needs no special path.

## Alternatives considered

- **A plain directory as the source of truth, app holds paths.** Rejected: it leaves rendition
  generation outside the app, which is the specific thing that made two aspect ratios hard in the
  first place, and it re-introduces safe path resolution. Its real advantage — browsability — is
  recovered by the export, and the export is better than the directory it replaces.
- **Active Storage with no export.** Rejected outright. It makes the collection recoverable only
  by someone with a running app, which is not an acceptable property for the only copy of a
  curated collection.
- **Export renditions as well as originals.** Rejected: derivable, and it multiplies the size of
  the backup without adding anything you couldn't regenerate.
- **Store display-sized images as the originals**, since that is what the current collection
  already is. Rejected: a 16:10 crop cannot yield a good 16:9 rendition, so this forecloses the
  second screen — and it is expensive to undo once records exist.
