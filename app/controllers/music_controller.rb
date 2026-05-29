class MusicController < ApplicationController
  before_action :authenticate_user!

  # GET /music/search?q=query
  # Returns an HTML fragment (no layout) listing matching albums.
  def search
    query   = params[:q].to_s.strip
    @results = query.length >= 2 ? MusicSearchService.new.search_albums(query) : []

    render layout: false
  end

  # GET /music/preview?itunes_id=123456
  # Returns a Turbo Frame with full album details + the log form pre-filled.
  def preview
    itunes_id = params[:itunes_id].to_s.strip

    if itunes_id.blank?
      render plain: "Missing itunes_id", status: :bad_request
      return
    end

    result = MusicSearchService.new.fetch_album_with_tracks(itunes_id)

    if result.nil?
      render plain: "Album not found", status: :not_found
      return
    end

    @album_data = result[:album]
    @tracks     = result[:tracks]

    render layout: false
  end
end
