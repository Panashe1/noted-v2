# Noted — Developer Documentation

Noted is a music-logging web application built with Ruby on Rails. Users discover music, log albums and individual tracks with ratings and reviews, follow other listeners, and receive AI-generated taste profiles and recommendations. Think Letterboxd, but for music.

---

## Documentation Index

| Document | What it covers |
|---|---|
| [MVC Architecture](./mvc-architecture.md) | Core Rails MVC patterns and how Noted uses them |
| [Views](./views.md) | Every page: what it renders, what data it needs, how interactions work |
| [Controllers](./controllers.md) | Every controller and action: routing, business logic, security |
| [Models](./models.md) | Database schema, associations, validations, callbacks, key methods |
| [Tests](./tests.md) | Test organisation, helpers, what is and isn't covered |
| [APIs & External Services](./apis.md) | iTunes Search API, Anthropic Claude API, error codes, failure modes |

---

## Tech Stack at a Glance

| Layer | Technology |
|---|---|
| Language | Ruby 3.3.0 |
| Framework | Rails 7.2.3 |
| Database | PostgreSQL |
| Background jobs | Sidekiq + Redis |
| Authentication | Devise |
| File storage | Active Storage (local disk in dev) |
| CSS | Tailwind CSS v4 via `tailwindcss-rails` |
| JavaScript | Hotwire (Turbo Drive + Turbo Frames + Stimulus) |
| Image processing | `image_processing` gem (libvips or mini_magick) |
| HTTP client | HTTParty |
| AI | Anthropic Claude API via `anthropic` gem |
| External music data | Apple iTunes Search API (free, no auth required) |

---

## Running the Application

```bash
# Install dependencies
bundle install

# Create and seed the database
rails db:create db:migrate

# Start Sidekiq (required for AI background jobs)
bundle exec sidekiq

# Start the dev server
bin/dev         # or: rails server
```

> **Note:** AI features require `ANTHROPIC_API_KEY` set in your environment.  
> iTunes search works without any API key.

---

## Key Design Decisions

### Two separate log types
Albums are logged via `ListenLog`; individual tracks via `TrackLog`. These are entirely independent — track logs do **not** affect the AI taste profile, which is driven only by album logs. This was an intentional design choice to keep the taste-profile signal clean.

### iTunes as the music database
Rather than maintaining a music catalogue ourselves, Noted pulls data from the Apple iTunes Search API on demand. Albums and tracks are persisted to the local database the first time a user interacts with them, so subsequent requests hit our database instead of iTunes.

### AI runs asynchronously
All Anthropic API calls (`AlbumContextJob`, `TasteProfileJob`) run in background Sidekiq workers so HTTP responses are never blocked waiting on AI. The taste profile regenerates automatically every fifth album log.

### Hotwire over heavy JavaScript
Noted uses Turbo Drive (full-page navigation without full reloads), Turbo Frames (partial-page updates for the search modal), and a small number of Stimulus controllers for interactive UI components. There is no separate API layer and no front-end framework.
