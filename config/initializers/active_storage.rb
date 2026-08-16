# Serve attachments through the app rather than by redirecting to a storage URL.
#
# The default redirect route costs an extra round trip on every image swap —
# cross-origin, on a device with a slow radio and a weak CPU. The kiosk swaps a
# CSS background on a timer, so that latency lands exactly where it is visible.
# See docs/adr/20260816-active-storage-with-round-trippable-export.md.
Rails.application.config.active_storage.resolve_model_to_route = :rails_storage_proxy
