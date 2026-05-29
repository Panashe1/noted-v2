class TasteProfileJob < ApplicationJob
  queue_as :ai

  def perform(user_id)
    user    = User.find(user_id)
    profile = ClaudeService.new.generate_taste_profile(user)

    user.update!(
      ai_taste_profile:             profile,
      taste_profile_generated_at:   Time.current
    ) if profile
  end
end
