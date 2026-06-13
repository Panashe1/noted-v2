# Rate limiting (rack-attack). Returns HTTP 429 when a client exceeds a limit.
#
# Goals:
#   • brute-force / credential-stuffing protection on login
#   • cap runaway cost on the AI-backed Discover endpoint (each query calls Claude)
#   • a global safety net against scrapers / abuse
#
# Paths are matched with end_with? because routes are wrapped in an optional (:locale)
# scope — both /users/sign_in and /es/users/sign_in must be covered.

# Shared store so limits hold across web workers/servers. Reuse the Redis that Sidekiq
# already requires (a separate logical DB avoids key collisions). In test we leave the
# default store untouched so throttles don't bleed across runs or require Redis — the
# rate-limit test installs its own in-memory store.
unless Rails.env.test?
  rate_limit_redis_url = ENV.fetch("RATE_LIMIT_REDIS_URL") { ENV.fetch("REDIS_URL", "redis://localhost:6379/1") }
  store_options = { url: rate_limit_redis_url }
  # Heroku Redis uses TLS (rediss://) with a self-signed cert — skip verification (still encrypted).
  store_options[:ssl_params] = { verify_mode: OpenSSL::SSL::VERIFY_NONE } if rate_limit_redis_url.start_with?("rediss://")
  Rack::Attack.cache.store = ActiveSupport::Cache::RedisCacheStore.new(**store_options)
end

### Throttles ###

# Login by IP — a human won't submit 10 logins/minute; a brute-forcer will.
Rack::Attack.throttle("login/ip", limit: 10, period: 60.seconds) do |req|
  req.ip if req.post? && req.path.end_with?("/users/sign_in")
end

# Login by email — catches credential stuffing that rotates IPs against one account.
Rack::Attack.throttle("login/email", limit: 10, period: 60.seconds) do |req|
  if req.post? && req.path.end_with?("/users/sign_in")
    req.params.dig("user", "email").to_s.downcase.strip.presence
  end
end

# Discover spends real money (Claude) — only count requests that actually run a query.
Rack::Attack.throttle("discover/ip", limit: 15, period: 60.seconds) do |req|
  req.ip if req.get? && req.path.end_with?("/discover") && req.params["q"].present?
end

# Global safety net against scraping / floods.
Rack::Attack.throttle("req/ip", limit: 300, period: 5.minutes, &:ip)

### Response ###

Rack::Attack.throttled_responder = lambda do |req|
  retry_after = (req.env["rack.attack.match_data"] || {})[:period].to_i
  [
    429,
    { "Content-Type" => "text/plain", "Retry-After" => retry_after.to_s },
    ["Too many requests. Please try again in #{retry_after} seconds.\n"]
  ]
end
