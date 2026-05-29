# app/jobs/taste_profile_job.rb
class TasteProfileJob < ApplicationJob
  queue_as :ai

  def perform(user_id)
    user = User.find(user_id)
    claude = ClaudeService.new
    profile = claude.generate_taste_profile(user)

    if profile
      user.update!(
        ai_taste_profile: profile,
        taste_profile_generated_at: Time.current
      )
    end
  end
end

# app/jobs/album_context_job.rb
class AlbumContextJob < ApplicationJob
  queue_as :ai

  def perform(album_id)
    album = Album.find(album_id)
    return if album.ai_context.present?  # already generated

    claude = ClaudeService.new
    context = claude.generate_album_context(album)

    album.update!(
      ai_context: context,
      ai_context_generated_at: Time.current
    ) if context
  end
end
