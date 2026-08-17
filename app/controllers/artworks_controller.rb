class ArtworksController < ApplicationController
  # 154 thumbnails on one page is roughly 8MB and 154 requests. Paged by hand
  # rather than with a gem: it is a limit, an offset and two links.
  PER_PAGE = 48

  def index
    @collections = Collection.by_name.includes(:artworks)
    @leader = Display.leader
    @current = @leader&.current_artwork
    @query = params[:q].to_s.strip

    scope = Artwork.includes(:artist, :collection, original_attachment: :blob).by_title
    scope = scope.matching(@query) if @query.present?

    if params[:collection].present?
      @collection = Collection.find_by(slug: params[:collection])
      scope = scope.where(collection: @collection)
    end

    @total = scope.count
    @page = [ params[:page].to_i, 1 ].max
    @pages = [ (@total / PER_PAGE.to_f).ceil, 1 ].max
    @page = @pages if @page > @pages

    @artworks = scope.limit(PER_PAGE).offset((@page - 1) * PER_PAGE)
  end

  def show
    @artwork = Artwork.find_by!(slug: params[:id])
    @displays = Display.active.select { |display| display.eligible_artworks.exists?(@artwork.id) }
  end
end
