class RecommendationsController < ApplicationController
  def index
    @query = params[:q].to_s.strip

    if @query.present?
      raw = ClaudeService.new.recommend(user: current_user, query: @query)
      @recommendations = enrich_with_itunes(parse_recommendations(raw))
    else
      @recommendations = []
    end
  end

  private

  def parse_recommendations(raw)
    return [] if raw.blank?

    # Claude sometimes wraps JSON in markdown fences despite being asked not to
    json_str = raw.gsub(/\A```(?:json)?\s*/i, "").gsub(/\s*```\z/, "").strip
    JSON.parse(json_str)
  rescue JSON::ParserError => e
    Rails.logger.error("[RecommendationsController] JSON parse error: #{e.message}")
    []
  end

  def enrich_with_itunes(recs)
    service = MusicSearchService.new

    recs.map do |rec|
      query   = "#{rec['artist']} #{rec['title']}"
      results = service.search_albums(query)
      best    = results.first

      rec.merge(
        "itunes_id" => best&.dig(:itunes_id),
        "cover_url" => best&.dig(:cover_url),
        "genre"     => best&.dig(:genre) || rec["genre"]
      )
    end
  end
end
