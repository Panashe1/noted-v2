class TracksController < ApplicationController
  def index
    @query = params[:q].to_s.strip

    base = Track.includes(:album).joins(:album)

    @tracks = if @query.length >= 2
      base.where("tracks.title ILIKE :q OR albums.title ILIKE :q OR albums.artist ILIKE :q", q: "%#{@query}%")
    else
      base
    end

    @tracks = @tracks.order("albums.artist, albums.title, tracks.position").page(params[:page]).per(50)
  end

  def show
    @track        = Track.includes(:album).find(params[:id])
    @album        = @track.album
    @album_tracks = @album.tracks # already ordered by position via default_scope
    @user_log     = current_user&.track_logs&.find_by(track: @track)
  end
end
