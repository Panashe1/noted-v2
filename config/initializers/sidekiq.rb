redis_url = ENV.fetch("REDIS_URL", "redis://localhost:6379/0")
redis_config = { url: redis_url }

# Heroku's managed Redis serves TLS (rediss://) with a self-signed certificate, which the
# Redis client rejects by default. Skip verification for TLS URLs — the connection is still
# encrypted and stays within Heroku's private network. Local dev (redis://) is untouched.
redis_config[:ssl_params] = { verify_mode: OpenSSL::SSL::VERIFY_NONE } if redis_url.start_with?("rediss://")

Sidekiq.configure_server { |config| config.redis = redis_config }
Sidekiq.configure_client { |config| config.redis = redis_config }
