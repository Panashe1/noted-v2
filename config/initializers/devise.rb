# frozen_string_literal: true

Devise.setup do |config|
  # The "From" address for Devise emails. Currently dormant — no Devise mailer is active
  # (password reset / :recoverable is disabled until an email provider is wired up). Kept
  # Noted-branded and ENV-overridable so it's correct the moment email is re-enabled.
  config.mailer_sender = ENV.fetch("MAILER_SENDER", "noreply@noted.app")

  require 'devise/orm/active_record'

  config.case_insensitive_keys = [:email]
  config.strip_whitespace_keys = [:email]
  config.skip_session_storage = [:http_auth]
  config.stretches = Rails.env.test? ? 1 : 12
  config.reconfirmable = true
  config.expire_all_remember_me_on_sign_out = true
  config.password_length = 6..128
  config.email_regexp = /\A[^@\s]+@[^@\s]+\z/
  config.reset_password_within = 6.hours
  config.sign_out_via = :delete
  config.responder.error_status = :unprocessable_entity
  config.responder.redirect_status = :see_other
end
