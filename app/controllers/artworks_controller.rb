class ArtworksController < ApplicationController
  def index
    @collections = Collection.by_name.includes(:artworks)
    @artworks = Artwork.includes(:artist, :collection, original_attachment: :blob).by_title
    @artworks = @artworks.where(collection: Collection.find_by(slug: params[:collection])) if params[:collection]
  end

  def show
    @artwork = Artwork.find_by!(slug: params[:id])
    @displays = Display.active.select { |display| display.eligible_artworks.exists?(@artwork.id) }
  end
end
