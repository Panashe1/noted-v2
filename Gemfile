source "https://rubygems.org"
ruby "3.3.0"

gem "rails", "~> 7.2.3"
gem "sprockets-rails"
gem "pg", "~> 1.1"
gem "puma", ">= 5.0"
gem "importmap-rails"
gem "turbo-rails"
gem "stimulus-rails"
gem "tailwindcss-rails"
gem "jbuilder"
gem "tzinfo-data", platforms: %i[ windows jruby ]
gem "bootsnap", require: false
gem "image_processing", "~> 1.2"

# Auth
gem "devise"
gem "devise-i18n"          # Translations for Devise's built-in views/messages

# Background jobs
gem "sidekiq", "~> 8.0"
gem "connection_pool", "~> 2.4"
gem "redis", ">= 4.0.1"

# Anthropic API
gem "anthropic"

# Music metadata
gem "httparty"

# Pagination
gem "kaminari"

# Internationalization — locale data (dates, numbers, AR errors) for ~70 languages
gem "rails-i18n"

group :development, :test do
  gem "dotenv-rails"
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false
  gem "rspec-rails"
  gem "factory_bot_rails"
  gem "faker"
  gem "i18n-tasks"          # Finds missing/unused keys, normalizes locale YAML
end

group :development do
  gem "web-console"
  gem "annotate"
end
