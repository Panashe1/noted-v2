namespace :albums do
  desc "Backfill iTunes metadata (itunes_id, cover art, apple_music_url) for albums that are missing it"
  task backfill_itunes: :environment do
    albums = Album.where(itunes_id: nil)
    total  = albums.count

    if total.zero?
      puts "All albums already have iTunes data. Nothing to do."
      next
    end

    puts "Backfilling #{total} album#{"s" if total != 1}...\n\n"

    service = MusicSearchService.new
    updated = 0
    skipped = 0

    albums.each do |album|
      query   = "#{album.artist} #{album.title}"
      results = service.search_albums(query)
      best    = results.first

      if best.nil?
        puts "  SKIP  #{album.artist} — #{album.title}  (no iTunes match)"
        skipped += 1
        next
      end

      album.update!(
        itunes_id:       best[:itunes_id],
        cover_image_url: best[:cover_url],
        apple_music_url: best[:apple_music_url],
        release_year:    album.release_year.presence || best[:release_year],
        genre:           album.genre.presence        || best[:genre]
      )

      # Enqueue track import in the background
      TrackImportJob.perform_later(album.id)

      puts "  OK    #{album.artist} — #{album.title}"
      puts "        iTunes ID #{best[:itunes_id]} | #{best[:track_count]} tracks | #{best[:genre]}"

      updated += 1
      sleep 0.3  # be polite to the iTunes API
    end

    puts "\n#{"─" * 50}"
    puts "Done — #{updated} updated, #{skipped} skipped"
  end
end
