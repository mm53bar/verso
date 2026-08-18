# Hand the proxy a path, never the bytes

## Context

Every image this app serves went through Ruby, by two different routes.

Display renditions went through `RenditionsController`, which buffers with
`send_data`. The browse UI's thumbnails went through Active Storage's own proxy
controller, reached by `image_tag artwork.thumbnail` and
`resolve_model_to_route = :rails_storage_proxy`.

The second route was slow enough to be worth complaining about, and measurement
found the cost was not where it looked. Serving the same 40KB thumbnail warm and
cached took 30ms; serving it on a cache miss had a **p90 of 516ms and a worst
case of 2.37 seconds**. Meanwhile `RenditionsController` served **2.3MB in a flat
165ms**, on a cache miss every single time. Fifty-seven times the data, a third
of the time, and a fraction of the variance.

The difference was not disk (a 3.5MB blob reads off this NAS in 33ms), not the
database (4.6ms of a 613ms request), and not file size. The two controllers
differ in exactly one thing: Active Storage's includes
`ActionController::Live`. That has already cost this app once — `Live::Buffer`
deletes `Content-Length` on the first write, which made every GET chunked with no
length and every HEAD answer 0 for an image megabytes long, and the Frame
integration refused the images outright. It also hands the body to a second
thread that checks out a database connection of its own, which is what
deadlocked production earlier the same day.

Thruster, which fronts Puma in this container, supports `X-Sendfile` and has it
enabled by default. `Rack::Sendfile` was already in the middleware stack.
`config.action_dispatch.x_sendfile_header` was never set, so the whole mechanism
sat idle at both ends.

## Decision

**Serve every image with `send_file`, from one controller, and let Thruster do
the I/O.**

- `config.action_dispatch.x_sendfile_header = "X-Sendfile"` in production only.
  `Rack::Sendfile` then rewrites any response whose body responds to `to_path`
  into an empty body plus the path, and Thruster serves the file with
  `sendfile(2)`. Puma is released when the headers are written, whatever the file
  size.
- `RenditionsController` gains a `variant` action for the named sizes, so
  thumbnails are addressed as `/artworks/:slug/variants/thumb.jpg` — by artwork
  and size, not by storage key. Views ask through `artwork_variant_url_for`.
- Both actions `send_file` when the blob is a real file, and fall back to
  `send_data` when it is not.

Only `send_file` is accelerated: `Rack::Sendfile` ignores a String body, so
`send_data` is left alone and stays correct.

## Consequences

Ruby stops carrying image bytes. The p90 and the 2.4s tail go with it, and they
go because Puma is no longer in the path rather than because it got faster at
being in it.

Thumbnail URLs are now stable. They used to embed a signed Active Storage variant
key, so regenerating a variant changed every URL on the page — which the brief
warned about and which nothing prevented.

**`Rack::Sendfile` sets `Content-Length: 0` and expects the proxy to restate it.**
That is the same wrong answer that broke the Frame, now load-bearing on Thruster
doing its half. So a HEAD returns *before* `send_file`, keeping the length this
controller computed, and the deployed GET path is verified on the wire rather
than assumed.

The two mechanisms collapse into one controller, so there is a single place where
this can go wrong again.

Requests still all reach Rails. Thruster has no document root and no location
blocks, so unlike nginx there is no way to serve a file without Rails routing the
request — the only choice is whether Rails answers with a path or with bytes.

**This is Disk-service only.** `path_for` exists on the Disk service and nowhere
else, so moving storage to S3 silently returns this to buffering rather than
raising. That is why the fallback is a runtime check on the service and on the
file, not an assumption.

## Alternatives considered

**Leave thumbnails on Active Storage's proxy and only fix renditions.** Argued
for and rejected on measurement. The reasoning was that thumbnails are 53KB and
already cache-hitting in Thruster, so the win looked small — but that reasoned
from cache hits, and the pain was entirely on the miss path. Cold thumbnails were
the slow thing.

**Raise Thruster's `MAX_CACHE_ITEM_SIZE` past the 1.79MB rendition.** Helps only
the repeat request, does nothing for a cold cache, and the cache empties on every
container recreate — which is every deploy.

**Redirect to Active Storage's URL instead of serving.** Costs a second round
trip, cross-origin, on a device with a slow radio, at the moment a screen is
swapping. Rejected in the storage ADR for that reason and still wrong.

**`X-Accel-Redirect`.** nginx's equivalent, which `Rack::Sendfile` also supports.
Needs an `X-Accel-Mapping` from URL space to filesystem space, which Thruster
does not provide because it does not need it — it shares a filesystem with Puma.

**A bigger connection pool alone.** Already done, and it stopped the deadlock,
but it buys headroom for a cost rather than removing the cost.
