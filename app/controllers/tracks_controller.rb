class TracksController < ApplicationController
  def index
    @query = params[:q].to_s.strip

    base = Track.includes(:album).joins(:album)

    if @query.length >= 2
      @tracks = base.where(
        "tracks.title ILIKE :q OR albums.title ILIKE :q OR albums.artist ILIKE :q",
        q: "%#{@query}%"
      ).order("albums.artist, albums.title, tracks.position").page(params[:page]).per(50)

      # Also search iTunes for tracks not already in our local library
      itunes_results  = MusicSearchService.new.search_tracks(@query)
      local_track_ids = Track.where(itunes_track_id: itunes_results.map { |t| t[:itunes_track_id] })
                             .pluck(:itunes_track_id).to_set
      @itunes_tracks  = itunes_results.reject { |t| local_track_ids.include?(t[:itunes_track_id]) }
    else
      @tracks        = base.order("albums.artist, albums.title, tracks.position").page(params[:page]).per(50)
      @itunes_tracks = []
    end

    # One aggregation query for all displayed tracks — prevents N+1 in the view
    @track_ratings = preload_track_ratings(@tracks)
  end

  def show
    @track        = Track.includes(:album).find(params[:id])
    @album        = @track.album
    @album_tracks = @album.tracks.to_a # already ordered by position via default_scope
    @user_log     = current_user&.track_logs&.find_by(track: @track)

    # Aggregate stats for the hero and sidebar tracklist
    @track_avg       = @track.average_rating
    @track_log_count = @track.log_count
    @track_ratings   = preload_track_ratings(@album_tracks)
  end

  # GET /tracks/from_itunes?itunes_track_id=XXX&itunes_album_id=YYY
  # Finds or creates the album + track from iTunes data, then redirects to the track page.
  def from_itunes
    itunes_track_id = params[:itunes_track_id].to_s.strip
    itunes_album_id = params[:itunes_album_id].to_s.strip

    if itunes_track_id.blank? || itunes_album_id.blank?
      redirect_to tracks_path, alert: "Missing track info." and return
    end

    # Already have this track locally? Jump straight there.
    track = Track.find_by(itunes_track_id: itunes_track_id)
    return redirect_to track_path(track) if track

    # Fetch full album + tracklist from iTunes
    result = MusicSearchService.new.fetch_album_with_tracks(itunes_album_id)

    if result.nil?
      redirect_to tracks_path, alert: "Couldn't load that track from iTunes. Try again." and return
    end

    album_data = result[:album]

    # Bug fixes:
    # - Wrap album + track creation in a transaction so a mid-loop failure
    #   doesn't leave an orphaned album with a partial tracklist (bug 4)
    # - Removed `if album.tracks.none?` guard — find_or_create_by is already
    #   idempotent and the guard caused a race with TrackImportJob (bug 2)
    track = ActiveRecord::Base.transaction do
      album = Album.find_by(itunes_id: album_data[:itunes_id])
      unless album
        album = Album.find_or_initialize_by(
          title:  album_data[:title].to_s.strip,
          artist: album_data[:artist].to_s.strip
        )
        album.assign_attributes(
          release_year:    album_data[:release_year],
          genre:           album_data[:genre],
          cover_image_url: album_data[:cover_url],
          itunes_id:       album_data[:itunes_id],
          apple_music_url: album_data[:apple_music_url]
        )
        album.save!
      end

      # Always run find_or_create_by — it's idempotent and safe under concurrency
      result[:tracks].each do |t|
        album.tracks.find_or_create_by(itunes_track_id: t[:itunes_track_id]) do |new_track|
          new_track.title       = t[:title]
          new_track.position    = t[:position]
          new_track.duration_ms = t[:duration_ms]
        end
      end

      # Return the specific track we want
      album.tracks.find_by(itunes_track_id: itunes_track_id)
    end

    if track
      redirect_to track_path(track)
    else
      redirect_to tracks_path, notice: "Added to library! Find your track by searching for it."
    end
  end
end
