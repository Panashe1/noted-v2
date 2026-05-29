class MusicSearchService
  SEARCH_URL  = "https://itunes.apple.com/search".freeze
  LOOKUP_URL  = "https://itunes.apple.com/lookup".freeze
  TIMEOUT     = 5 # seconds

  # Search for albums matching a query string.
  # Returns an array of hashes, e.g.:
  #   [{ itunes_id:, title:, artist:, release_year:, genre:, cover_url:, apple_music_url: }, ...]
  def search_albums(query)
    return [] if query.blank?

    response = HTTParty.get(
      SEARCH_URL,
      query:   { term: query, entity: "album", limit: 8, media: "music" },
      timeout: TIMEOUT
    )

    return [] unless response.success?

    data = JSON.parse(response.body)
    results = data["results"] || []

    results.map { |r| parse_album_result(r) }.compact
  rescue StandardError => e
    Rails.logger.error("[MusicSearchService#search_albums] #{e.message}")
    []
  end

  # Search for individual songs/tracks (including singles).
  # Returns an array of hashes, e.g.:
  #   [{ itunes_track_id:, itunes_album_id:, title:, artist:, album_title:,
  #      duration_ms:, position:, cover_url:, release_year:, is_single: }, ...]
  def search_tracks(query)
    return [] if query.blank?

    response = HTTParty.get(
      SEARCH_URL,
      query:   { term: query, entity: "song", limit: 20, media: "music" },
      timeout: TIMEOUT
    )

    return [] unless response.success?

    data    = JSON.parse(response.body)
    results = data["results"] || []

    results
      .select { |r| r["wrapperType"] == "track" && r["kind"] == "song" }
      .map    { |r| parse_track_result(r) }
      .compact
  rescue StandardError => e
    Rails.logger.error("[MusicSearchService#search_tracks] #{e.message}")
    []
  end

  # Fetch a single album's full metadata including its tracklist.
  # Returns a hash: { album: { itunes_id:, ... }, tracks: [{ title:, position:, duration_ms:, itunes_track_id: }, ...] }
  def fetch_album_with_tracks(itunes_id)
    response = HTTParty.get(
      LOOKUP_URL,
      query:   { id: itunes_id, entity: "song", country: "us" },
      timeout: TIMEOUT
    )

    return nil unless response.success?

    data    = JSON.parse(response.body)
    results = data["results"] || []

    # First result is always the album itself; rest are tracks
    album_data = results.find { |r| r["wrapperType"] == "collection" }
    track_data = results.select { |r| r["wrapperType"] == "track" }
                        .sort_by { |t| t["trackNumber"].to_i }

    return nil unless album_data

    tracks = track_data.map do |t|
      {
        title:           t["trackName"],
        position:        t["trackNumber"].to_i,
        duration_ms:     t["trackTimeMillis"].to_i,
        itunes_track_id: t["trackId"].to_s
      }
    end

    {
      album:  parse_album_result(album_data),
      tracks: tracks
    }
  rescue StandardError => e
    Rails.logger.error("[MusicSearchService#fetch_album_with_tracks] #{e.message}")
    nil
  end

  private

  def parse_album_result(result)
    return nil unless result["collectionId"]

    year = begin
      Date.parse(result["releaseDate"]).year
    rescue StandardError
      nil
    end

    {
      itunes_id:       result["collectionId"].to_s,
      title:           result["collectionName"],
      artist:          result["artistName"],
      release_year:    year,
      genre:           result["primaryGenreName"],
      cover_url:       result["artworkUrl100"]&.gsub("100x100bb", "600x600bb"),
      apple_music_url: result["collectionViewUrl"],
      track_count:     result["trackCount"].to_i
    }
  end
end
