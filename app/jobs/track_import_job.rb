class TrackImportJob < ApplicationJob
  queue_as :default

  def perform(album_id)
    album = Album.find_by(id: album_id)
    return unless album&.itunes_id.present?
    return if album.tracks.exists? # already imported

    result = MusicSearchService.new.fetch_album_with_tracks(album.itunes_id)
    return unless result && result[:tracks].any?

    result[:tracks].each do |t|
      album.tracks.find_or_create_by(itunes_track_id: t[:itunes_track_id]) do |track|
        track.title       = t[:title]
        track.position    = t[:position]
        track.duration_ms = t[:duration_ms]
      end
    end

    Rails.logger.info("[TrackImportJob] Imported #{album.tracks.count} tracks for album #{album.id}")
  end
end
