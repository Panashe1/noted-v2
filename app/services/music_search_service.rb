class MusicSearchService
  SEARCH_URL   = "https://itunes.apple.com/search".freeze
  LOOKUP_URL   = "https://itunes.apple.com/lookup".freeze
  TOP_FEED_URL = "https://itunes.apple.com/us/rss/topalbums/limit=%d/json".freeze
  TIMEOUT      = 5 # seconds

  # Search for albums matching a query string.
  # Returns an array of up to 8 hashes:
  #   [{ itunes_id:, title:, artist:, release_year:, genre:, cover_url:, apple_music_url: }, ...]
  #
  # Strategy: song-entity search first, album-entity search as supplement.
  #
  # Why song-first? iTunes' entity=album search silently omits a large number of real
  # albums — smaller/independent artists, recent releases, and explicit albums are
  # frequently missing. The entity=song index is far broader; deduplicating song results
  # by collectionId reconstructs the album list and captures what album search misses.
  # Album-entity results are then added for anything the song search didn't surface.
  def search_albums(query)
    return [] if query.blank?

    song_hits  = search_albums_via_song_entity(query)
    album_hits = search_by_album_entity(query)

    # Song-derived albums lead; album-entity fills in anything not already found.
    seen_ids = song_hits.map { |a| a[:itunes_id] }.to_set
    merged   = song_hits + album_hits.reject { |a| seen_ids.include?(a[:itunes_id]) }
    merged.first(8)
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

  # Fetch the current Apple Music top albums chart.
  # Returns an array of up to `limit` hashes:
  #   [{ itunes_id:, title:, artist:, release_year:, cover_url:, apple_music_url:, chart_rank: }, ...]
  def fetch_top_albums(limit: 20)
    url      = TOP_FEED_URL % limit
    response = HTTParty.get(url, timeout: TIMEOUT)

    return [] unless response.success?

    data    = JSON.parse(response.body)
    entries = data.dig("feed", "entry") || []

    entries.each_with_index.map { |e, idx| parse_chart_entry(e, idx + 1) }.compact
  rescue StandardError => e
    Rails.logger.error("[MusicSearchService#fetch_top_albums] #{e.message}")
    []
  end

  private

  # entity=album search — good for well-catalogued mainstream releases.
  def search_by_album_entity(query)
    response = HTTParty.get(
      SEARCH_URL,
      query:   { term: query, entity: "album", limit: 8, media: "music" },
      timeout: TIMEOUT
    )
    return [] unless response.success?

    (JSON.parse(response.body)["results"] || []).map { |r| parse_album_result(r) }.compact
  rescue StandardError
    []
  end

  # entity=song search, deduplicated to unique albums by collectionId.
  # Catches albums that iTunes doesn't surface via entity=album — common with
  # smaller/independent artists, newer releases, and explicit albums.
  # Song results carry identical album-level metadata fields so parse_album_result works directly.
  def search_albums_via_song_entity(query)
    response = HTTParty.get(
      SEARCH_URL,
      query:   { term: query, entity: "song", limit: 25, media: "music" },
      timeout: TIMEOUT
    )
    return [] unless response.success?

    seen = Set.new
    (JSON.parse(response.body)["results"] || []).filter_map do |r|
      cid = r["collectionId"]&.to_s
      next if cid.nil? || seen.include?(cid)
      seen.add(cid)
      parse_album_result(r)
    end
  rescue StandardError
    []
  end

  def parse_chart_entry(entry, rank)
    itunes_id = entry.dig("id", "attributes", "im:id")
    return nil unless itunes_id

    # Images come as an array sorted by size — take the largest (170x170) and upscale
    raw_image = entry.dig("im:image")&.last&.dig("label")
    cover     = raw_image&.gsub(/\d+x\d+bb/, "600x600bb")

    release_year = begin
      Date.parse(entry.dig("im:releaseDate", "label")).year
    rescue StandardError
      nil
    end

    {
      itunes_id:       itunes_id,
      title:           entry.dig("im:name", "label"),
      artist:          entry.dig("im:artist", "label"),
      release_year:    release_year,
      cover_url:       cover,
      apple_music_url: entry.dig("link", "attributes", "href"),
      chart_rank:      rank
    }
  end

  def parse_track_result(result)
    return nil unless result["trackId"] && result["collectionId"]

    year = begin
      Date.parse(result["releaseDate"]).year
    rescue StandardError
      nil
    end

    total_ms = result["trackTimeMillis"].to_i
    duration = if total_ms.positive?
      total_s = total_ms / 1000
      format("%d:%02d", total_s / 60, total_s % 60)
    end

    {
      itunes_track_id: result["trackId"].to_s,
      itunes_album_id: result["collectionId"].to_s,
      title:           result["trackName"],
      artist:          result["artistName"],
      album_title:     result["collectionName"],
      duration_ms:     total_ms,
      duration:        duration,
      position:        result["trackNumber"].to_i,
      cover_url:       result["artworkUrl100"]&.gsub("100x100bb", "60x60bb"),
      release_year:    year,
      is_single:       result["collectionType"] == "Single"
    }
  end

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
