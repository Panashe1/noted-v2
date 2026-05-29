class ClaudeService
  MODEL      = "claude-sonnet-4-20250514"
  MAX_TOKENS = 1024

  def initialize
    @client = Anthropic::Client.new(api_key: ENV["ANTHROPIC_API_KEY"])
  end

  def generate_taste_profile(user)
    logs = user.listen_logs.includes(:album).order(listened_on: :desc).limit(50)
    return nil if logs.empty?

    album_list = logs.map do |log|
      "#{log.album.artist} — #{log.album.title} (#{log.album.genre}, rated #{log.rating}/10)"
    end.join("\n")

    call_api(<<~PROMPT)
      You are a music critic and cultural analyst. Based on the following listening log,
      write a 3–4 sentence taste profile for this listener. Be specific, insightful,
      and avoid generic descriptions. Reference actual patterns you notice.

      Listening log:
      #{album_list}

      Write the profile in second person (e.g. "You gravitate toward...").
      Be evocative and precise — this will appear on their public profile.
    PROMPT
  end

  def generate_album_context(album)
    call_api(<<~PROMPT)
      You are a music encyclopaedist. Write a concise 2–3 sentence context card for:

      Artist: #{album.artist}
      Album: #{album.title}
      Year: #{album.release_year}
      Genre: #{album.genre}

      Cover its cultural significance, sonic character, and why it matters.
      Be specific — name influences, era, or notable aspects. Avoid clichés.
      Do not start with the album name.
    PROMPT
  end

  def assist_review(album:, rating:, user_notes: nil)
    notes_section = user_notes.present? ? "Their rough notes: \"#{user_notes}\"" : "They haven't written anything yet."

    call_api(<<~PROMPT)
      A music listener just finished #{album.artist} — #{album.title} and rated it #{rating}/10.
      #{notes_section}

      Help them write a short, honest review (3–5 sentences). Match the tone to the rating:
      high ratings should feel enthusiastic but not gushing; low ratings should be fair, not cruel.
      Write in first person as if you are the listener. Be specific to this album.
      Return only the review text — no preamble.
    PROMPT
  end

  def recommend(user:, query:)
    logs = user.listen_logs.includes(:album).order(rating: :desc).limit(30)
    top_albums = logs.any? ?
      logs.map { |l| "#{l.album.artist} — #{l.album.title} (#{l.rating}/10)" }.join("\n") :
      "(no listening history yet)"

    call_api(<<~PROMPT)
      You are a music recommendation engine with great taste.

      This listener's top-rated albums:
      #{top_albums}

      Their request: "#{query}"

      Suggest exactly 5 albums. Return ONLY a valid JSON array — no markdown, no explanation, no code block.
      Each object must have these exact keys: title, artist, year, description.
      "description" should be one compelling sentence explaining why it fits the request.
      "year" should be an integer.
      Example format:
      [{"title":"In Rainbows","artist":"Radiohead","year":2007,"description":"Lush electronic textures meet Yorke's most emotionally raw vocal performances."}]
    PROMPT
  end

  def taste_compatibility(user_a, user_b)
    call_api(<<~PROMPT)
      Compare the music taste of two listeners:

      Listener A top artists: #{top_artists(user_a)}
      Listener B top artists: #{top_artists(user_b)}

      Write 2 sentences about their compatibility — what they share, how they differ.
      Give a compatibility score out of 100 at the end in format: "Compatibility: XX/100"
    PROMPT
  end

  private

  def top_artists(user)
    user.listen_logs.includes(:album)
        .group_by { |l| l.album.artist }
        .transform_values { |logs| logs.sum(&:rating).to_f / logs.size }
        .sort_by { |_, avg| -avg }
        .first(10)
        .map { |artist, avg| "#{artist} (avg #{avg.round(1)}/10)" }
        .join(", ")
  end

  def call_api(prompt)
    response = @client.messages.create(
      model:      MODEL,
      max_tokens: MAX_TOKENS,
      messages:   [{ role: "user", content: prompt }]
    )
    response.content.first.text
  rescue Anthropic::Errors::Error => e
    Rails.logger.error("[ClaudeService] API error: #{e.class} — #{e.message}")
    raise e if Rails.env.development?
    nil
  end
end
