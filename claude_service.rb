# app/services/claude_service.rb
#
# Central wrapper around the Anthropic API.
# All AI features in Soundlog route through this class.

class ClaudeService
  MODEL = "claude-sonnet-4-20250514"
  MAX_TOKENS = 1024

  def initialize
    @client = Anthropic::Client.new(api_key: ENV["ANTHROPIC_API_KEY"])
  end

  # ------------------------------------------------------------------
  # 1. TASTE PROFILE
  # Generates a personalised music taste summary from a user's log.
  # Called async via TasteProfileJob.
  # ------------------------------------------------------------------
  def generate_taste_profile(user)
    logs = user.listen_logs.includes(:album).order(listened_on: :desc).limit(50)
    return nil if logs.empty?

    album_list = logs.map do |log|
      "#{log.album.artist} — #{log.album.title} (#{log.album.genre}, rated #{log.rating}/10)"
    end.join("\n")

    prompt = <<~PROMPT
      You are a music critic and cultural analyst. Based on the following listening log,
      write a 3–4 sentence taste profile for this listener. Be specific, insightful,
      and avoid generic descriptions. Reference actual patterns you notice.

      Listening log:
      #{album_list}

      Write the profile in second person (e.g. "You gravitate toward...").
      Be evocative and precise — this will appear on their public profile.
    PROMPT

    call_api(prompt)
  end

  # ------------------------------------------------------------------
  # 2. ALBUM CONTEXT CARD
  # Generates rich editorial context for an album when it's first logged.
  # ------------------------------------------------------------------
  def generate_album_context(album)
    prompt = <<~PROMPT
      You are a music encyclopaedist. Write a concise 2–3 sentence context card for:

      Artist: #{album.artist}
      Album: #{album.title}
      Year: #{album.release_year}
      Genre: #{album.genre}

      Cover its cultural significance, sonic character, and why it matters.
      Be specific — name influences, era, or notable aspects. Avoid clichés.
      Do not start with the album name.
    PROMPT

    call_api(prompt)
  end

  # ------------------------------------------------------------------
  # 3. REVIEW ASSISTANT
  # Helps a user articulate their thoughts about an album.
  # ------------------------------------------------------------------
  def assist_review(album:, rating:, user_notes: nil)
    notes_section = user_notes.present? ? "Their rough notes: \"#{user_notes}\"" : "They haven't written anything yet."

    prompt = <<~PROMPT
      A music listener just finished #{album.artist} — #{album.title} and rated it #{rating}/10.
      #{notes_section}

      Help them write a short, honest review (3–5 sentences). Match the tone to the rating:
      high ratings should feel enthusiastic but not gushing; low ratings should be fair, not cruel.
      Write in first person as if you are the listener. Be specific to this album.
      Return only the review text — no preamble.
    PROMPT

    call_api(prompt)
  end

  # ------------------------------------------------------------------
  # 4. CONVERSATIONAL RECOMMENDATION
  # Answers a natural-language "what should I listen to?" query.
  # ------------------------------------------------------------------
  def recommend(user:, query:)
    logs = user.listen_logs.includes(:album).order(rating: :desc).limit(30)
    top_albums = logs.map { |l| "#{l.album.artist} — #{l.album.title} (#{l.rating}/10)" }.join("\n")

    prompt = <<~PROMPT
      You are a music recommendation engine with taste and personality.

      This listener's top-rated albums:
      #{top_albums}

      Their request: "#{query}"

      Suggest 3 albums they haven't logged, with a one-sentence reason for each.
      Format each suggestion as:
      [Artist] — [Album] ([Year]): [reason]
    PROMPT

    call_api(prompt)
  end

  # ------------------------------------------------------------------
  # 5. COMPATIBILITY SCORE
  # Compares two users' taste and returns a narrative compatibility summary.
  # ------------------------------------------------------------------
  def taste_compatibility(user_a, user_b)
    def top_artists(user)
      user.listen_logs.includes(:album)
          .group_by { |l| l.album.artist }
          .transform_values { |logs| logs.sum(&:rating).to_f / logs.size }
          .sort_by { |_, avg| -avg }
          .first(10)
          .map { |artist, avg| "#{artist} (avg #{avg.round(1)}/10)" }
          .join(", ")
    end

    prompt = <<~PROMPT
      Compare the music taste of two listeners:

      Listener A top artists: #{top_artists(user_a)}
      Listener B top artists: #{top_artists(user_b)}

      Write 2 sentences about their compatibility — what they share, how they differ.
      Give a compatibility score out of 100 at the end in format: "Compatibility: XX/100"
    PROMPT

    call_api(prompt)
  end

  private

  def call_api(prompt)
    response = @client.messages(
      parameters: {
        model: MODEL,
        max_tokens: MAX_TOKENS,
        messages: [{ role: "user", content: prompt }]
      }
    )
    response.dig("content", 0, "text")
  rescue Anthropic::Error => e
    Rails.logger.error("[ClaudeService] API error: #{e.message}")
    nil
  end
end
