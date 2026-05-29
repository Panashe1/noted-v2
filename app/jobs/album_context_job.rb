class AlbumContextJob < ApplicationJob
  queue_as :ai

  def perform(album_id)
    album = Album.find(album_id)
    return if album.ai_context.present?

    context = ClaudeService.new.generate_album_context(album)

    album.update!(
      ai_context:               context,
      ai_context_generated_at:  Time.current
    ) if context
  end
end
