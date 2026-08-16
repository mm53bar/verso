# Keeps the human-readable copy of the collection current. Idempotent by
# checksum, so a run after the first copies only what actually changed and the
# schedule can be frequent without costing anything.
class ArtworkExportJob < ApplicationJob
  queue_as :default

  def perform(path: Verso.export_root)
    result = ArtworkExporter.new(path: path).call

    Rails.logger.info(
      "[verso] exported #{result.total} artworks to #{result.path} " \
      "(#{result.written} written, #{result.unchanged} unchanged)"
    )

    result.errors.each { |error| Rails.logger.warn("[verso] export: #{error}") }

    result
  end
end
