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
  end

  def show
    @track        = Track.includes(:album).find(params[:id])
    @album        = @track.album
    @album_tracks = @album.tracks # already ordered by position via default_scope
    @user_log     = current_user&.track_logs&.find_by(track: @track)
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

    # Find or create the album record
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

    # Import all tracks for this album if not already done
    if album.tracks.none?
      result[:tracks].each do |t|
        album.tracks.find_or_create_by(itunes_track_id: t[:itunes_track_id]) do |new_track|
          new_track.title       = t[:title]
          new_track.position    = t[:position]
          new_track.duration_ms = t[:duration_ms]
        end
      end
    end

    # Find the specific track the user clicked
    track = album.tracks.find_by(itunes_track_id: itunes_track_id)

    if track
      redirect_to track_path(track)
    else
      redirect_to album_path(album), notice: "Added to library! Find your track in the tracklist."
    end
  end
end
