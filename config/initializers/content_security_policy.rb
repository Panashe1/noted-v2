# Be sure to restart your server when you modify this file.
#
# Content Security Policy — hardened now that all inline JavaScript has been
# moved into Stimulus controllers. `script-src` does NOT permit 'unsafe-inline':
# the only inline scripts are importmap-rails' bootstrap tags, which are allowed
# via the per-request nonce configured at the bottom of this file.
#
# See: https://guides.rubyonrails.org/security.html#content-security-policy-header

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src      :self
    policy.base_uri         :self
    policy.form_action      :self
    policy.frame_ancestors  :none   # anti-clickjacking: app may not be iframed
    policy.object_src       :none

    # Application JS is served from /assets via importmap (same origin). The inline
    # importmap bootstrap scripts are permitted through the nonce, NOT 'unsafe-inline'.
    policy.script_src       :self

    # 'unsafe_inline' is required for inline style="" attributes (e.g. font-family,
    # letter-spacing in the layout) and Turbo's injected progress-bar <style>.
    # Inline style *attributes* cannot carry a nonce, so style-src is deliberately
    # NOT added to the nonce directives below — a nonce would void 'unsafe-inline'.
    policy.style_src        :self, :unsafe_inline, "https://fonts.googleapis.com"

    # Google Fonts font files.
    policy.font_src         :self, "https://fonts.gstatic.com"

    #  :self            -> Active Storage avatars (local disk service in dev)
    #  data:            -> small inline data-URI images (defensive)
    #  blob:            -> avatar live-preview (URL.createObjectURL in avatar_preview_controller)
    #  *.mzstatic.com   -> Apple Music cover art (is1-ssl … is5-ssl.mzstatic.com)
    policy.img_src          :self, :data, :blob, "https://*.mzstatic.com"

    # Same-origin XHR/fetch: Turbo navigations & frames, music search/preview endpoints.
    policy.connect_src      :self
  end

  # Per-request nonce for the inline importmap bootstrap scripts.
  # Only script-src is nonced — keeping style-src on 'unsafe-inline' (above) so
  # inline style attributes keep working.
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]

  # To audit without breaking anything, flip this on, watch the browser console
  # for violations, then turn it back off to enforce.
  # config.content_security_policy_report_only = true
end
