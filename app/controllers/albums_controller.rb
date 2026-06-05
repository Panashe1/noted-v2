class AlbumsController < ApplicationController
  before_action :authenticate_user!, only: [:from_itunes]

  def show
    @album         = Album.find(params[:id])
    @logs          = @album.listen_logs.includes(:user).order(created_at: :desc)
    @user_log      = current_user&.listen_logs&.find_by(album: @album)
    @album_tracks  = @album.tracks.to_a
    @track_ratings = preload_track_ratings(@album_tracks)
  end

  def index
    # Genre filter — the available options and the currently-active selection.
    # Intersecting with @genres sanitises the params against arbitrary/stale values.
    @genres        = Album.where.not(genre: [nil, ""]).distinct.order(:genre).pluck(:genre)
    @active_genres = Array(params[:genres]).select(&:present?) & @genres

    scope   = Album.order(created_at: :desc)
    scope   = scope.where(genre: @active_genres) if @active_genres.any?
    @albums = scope.page(params[:page])

    # The iTunes charts are only needed on a full page render. When the genre
    # filter refreshes just the Community Library Turbo Frame, skip the external
    # call entirely — the charts section is gated on @top_albums.any?.
    if turbo_frame_request?
      @top_albums         = []
      @chart_local_albums = {}
    else
      @top_albums         = MusicSearchService.new.fetch_top_albums(limit: 20)
      chart_itunes_ids    = @top_albums.map { |a| a[:itunes_id] }
      @chart_local_albums = Album.where(itunes_id: chart_itunes_ids).index_by(&:itunes_id)
    end
  end

  # GET /albums/from_itunes?itunes_id=123456
  # Finds or creates an album from iTunes data, then redirects to its show page.
  # Called when a user clicks a Discover recommendation.
  def from_itunes
    itunes_id = params[:itunes_id].to_s.strip

    if itunes_id.blank?
      redirect_to recommendations_path, alert: "No album ID supplied."
      return
    end

    # Already in our library?
    album = Album.find_by(itunes_id: itunes_id)

    unless album
      result = MusicSearchService.new.fetch_album_with_tracks(itunes_id)

      if result.nil?
        redirect_to recommendations_path, alert: "Couldn't find that album. Try again."
        return
      end

      data  = result[:album]
      album = Album.find_or_initialize_by(
        title:  data[:title].to_s.strip,
        artist: data[:artist].to_s.strip
      )

      album.assign_attributes(
        release_year:    data[:release_year],
        genre:           data[:genre],
        cover_image_url: data[:cover_url],
        itunes_id:       data[:itunes_id],
        apple_music_url: data[:apple_music_url]
      )

      album.save!
    end

    redirect_to album_path(album)
  end
end
