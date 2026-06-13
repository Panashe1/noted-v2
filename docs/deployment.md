# Deployment checklist

Everything needed to take **Noted** live. The code is launch-ready (see the production
hardening in git history); what remains is **configuration**. Work top to bottom.

Stack: Ruby 3.3.0 · Rails 7.2.3 · PostgreSQL · Redis · Puma (web) · Sidekiq (jobs).
No Node build step — JavaScript is served via importmap; CSS is built by `tailwindcss-rails`.

---

## 1. Backing services to provision

| Service | Used for | Notes |
|---|---|---|
| **PostgreSQL** | primary database | the only datastore of record |
| **Redis** | Sidekiq queue **and** rack-attack rate-limit counters | a single instance is fine |

Both are required. Without **Redis + a running Sidekiq process**, the AI features
(taste profiles, album context cards) silently never generate — the jobs just queue
forever.

## 2. Processes to run

| Process | Command | Required? |
|---|---|---|
| Web | `bundle exec puma -C config/puma.rb` (or `bin/rails server`) | yes |
| Worker | `bundle exec sidekiq` | yes (AI background jobs) |

There is no production `Procfile` yet (only `Procfile.dev`). Add one, or configure the two
process types in your platform's dashboard. Minimal `Procfile`:

```
web: bundle exec puma -C config/puma.rb
worker: bundle exec sidekiq
release: bin/rails db:migrate
```

## 3. Environment variables

Set these on the host (the dev `.env` is git-ignored and won't ship).

| Variable | Required | Purpose |
|---|---|---|
| `RAILS_MASTER_KEY` | **yes** | Decrypts `config/credentials.yml.enc`. Production now **refuses to boot without it** (`config.require_master_key = true`). Value = contents of `config/master.key`. |
| `SECRET_KEY_BASE` | yes* | Session/cookie signing. *Provided automatically via credentials (the master key) — or set it explicitly if your platform expects it. |
| `DATABASE_URL` | **yes** | `postgres://user:pass@host:5432/noted_production` |
| `REDIS_URL` | **yes** | `redis://host:6379/0` — Sidekiq + rate limiting |
| `ANTHROPIC_API_KEY` | for AI | Discover, taste profiles, album context. Without it those features no-op; iTunes/logging still work. |
| `APP_HOST` | recommended | Your domain(s) for Host-header protection. Comma-separated; prefix a dot for subdomains, e.g. `noted.app,.noted.app`. Unset = permissive (works, but no protection). |
| `RATE_LIMIT_REDIS_URL` | optional | Point rack-attack at a **separate Redis DB** from Sidekiq (e.g. `redis://host:6379/1`). Defaults to `REDIS_URL`. |
| `MAILER_SENDER` | optional | Dormant — no email is sent yet (password reset disabled). |
| `RAILS_LOG_LEVEL` | optional | Defaults to `info`. |
| `RAILS_MAX_THREADS` | optional | Puma threads = DB pool size; tune together. |

## 4. Build & release steps

```bash
bundle install --without development test
bin/rails assets:precompile     # builds Tailwind CSS + digests assets (config.assets.compile = false)
bin/rails db:migrate            # run in the release phase, before new code serves traffic
```

No seed data is needed — albums/tracks are imported from iTunes on demand.

---

## 5. Critical gotchas (read these — they're specific to this app)

### 5a. Avatars will disappear on redeploy unless you configure cloud storage
`config.active_storage.service = :local` (disk). On ephemeral hosts (Heroku, Render, Fly,
containers) the disk is wiped on every deploy/restart, so uploaded avatars vanish.
**Fix:** configure S3/GCS/Azure in `config/storage.yml` (commented examples are there) and
point `config.active_storage.service` at it in `production.rb`. If you're on a host with a
persistent volume, `:local` is acceptable.

### 5b. HTTPS / proxy headers
`config.force_ssl = true` is on. Your platform must terminate TLS and forward
`X-Forwarded-Proto: https`. If the proxy talks **plain HTTP** to the app, also set
`config.assume_ssl = true` — otherwise you'll get a redirect loop.

### 5c. Real client IP (so rate limiting works)
rack-attack throttles by `request.ip`. Behind a load balancer/CDN, every request can look
like it comes from the proxy's IP — meaning **all users share one bucket**. Rails trusts a
default set of private ranges via `X-Forwarded-For`; confirm your platform's setup, and if
needed set `config.action_dispatch.trusted_proxies` to your proxy's ranges. Verify after
deploy that throttles trigger per-client, not globally.

### 5d. Health check
`GET /up` is the health endpoint (already excluded from Host authorization). Point your
platform's health check at it.

---

## 6. Post-deploy smoke test

1. `GET /up` → 200.
2. Home/login page loads over **https** (no redirect loop → 5b is correct).
3. Sign up a user, log in, log out.
4. Log an album via the modal (exercises the live iTunes search + persistence).
5. Open an album page; confirm the AI **context card** appears within a minute → proves
   **Sidekiq + `ANTHROPIC_API_KEY`** are working. If it never appears, the worker or the key
   is misconfigured.
6. Upload an avatar; reload → it persists (and survives a redeploy only if 5a is handled).
7. Visit `/es` → UI is in Spanish.
8. Hammer login ~12 times with a wrong password → the last attempts return **429**
   (rate limiting live). If they don't, check 5c (client IP).

---

## 7. Known deferred items (not blockers, but track them)

- **Password reset is disabled.** Re-enable by adding `:recoverable` back to the `User`
  model, restoring the login-page link + `auth.login.forgot_password` key, and configuring
  an email provider: SMTP settings + `config.action_mailer.default_url_options = { host: APP_HOST }`
  in `production.rb`, plus `MAILER_SENDER`.
- **Rails 7.2 end-of-life: 2026-08-09.** Plan a Rails 8 upgrade in the coming months
  (Brakeman flags this as an unmaintained-dependency warning).
- **Discover latency.** `/discover` makes a synchronous Claude call + up to 5 sequential
  iTunes lookups — worst case several seconds. Consider caching the iTunes chart feed and/or
  moving enrichment async if it becomes a problem under load.
- **Error monitoring.** No Sentry/Honeybadger yet — recommended before meaningful traffic.
