# Onboarding: Noted + Ruby on Rails (for complete beginners)

This guide assumes you've never used Rails and have never seen this project. By the
end you'll understand **how Rails works**, **how Noted is built**, and **why** the code
is written the way it is. Every "best practice" links to an authoritative source.

> Companion docs (deeper dives): [MVC](./mvc-architecture.md) · [Views](./views.md) ·
> [Controllers](./controllers.md) · [Models](./models.md) · [Tests](./tests.md) · [APIs](./apis.md)

---

# Part 1 — Ruby on Rails in plain English

## 1.1 What Rails is, and its two big ideas

Ruby on Rails is a **web framework** written in the Ruby language. It gives you a
ready-made structure for building a database-backed website so you don't reinvent
routing, database access, HTML rendering, etc.

Two philosophies shape *everything*:

- **Convention over Configuration (CoC).** Rails guesses sensible defaults from names.
  A `Track` model automatically maps to a `tracks` table; a `TracksController`
  automatically renders `app/views/tracks/*`. You write *less* config because you
  *follow conventions*. → [The Rails Doctrine](https://rubyonrails.org/doctrine)
- **MVC (Model–View–Controller).** Code is split into three responsibilities so each
  stays small and testable. More below.

Why this matters: because everyone follows the same conventions, any Rails developer
can open this project and immediately know where things live. That's a real,
measurable productivity win — it's the whole pitch of Rails.
→ [Getting Started with Rails](https://guides.rubyonrails.org/getting_started.html)

## 1.2 The request lifecycle (the single most important diagram)

When your browser asks for a page, here's the journey:

```
Browser → Router → Controller → Model (database) → View (HTML) → Browser
```

Concretely, for `GET /tracks/42`:

1. **Router** (`config/routes.rb`) matches the URL to `TracksController#show`.
2. **Controller** (`app/controllers/tracks_controller.rb`) runs `show`: it asks the
   **Model** for data (`Track.find(42)`) and stuffs it in instance variables (`@track`).
3. **View** (`app/views/tracks/show.html.erb`) turns `@track` into HTML.
4. HTML goes back to the browser.

Memorise this loop — *every* feature in every Rails app is a variation of it.
→ [Action Controller Overview](https://guides.rubyonrails.org/action_controller_overview.html)

## 1.3 Where everything lives (directory tour)

```
app/
  controllers/   # traffic cops: receive requests, fetch data, pick a view
  models/        # the data + business rules (one class per database table)
  views/         # HTML templates (.html.erb = HTML with embedded Ruby)
  javascript/    # Stimulus controllers (small JS behaviours)
  services/      # plain Ruby classes for logic that isn't a model or controller
  jobs/          # background tasks (run outside the web request)
  helpers/       # small view helper methods
  assets/stylesheets/  # CSS
config/
  routes.rb      # URL → controller mapping
  locales/       # translation files (en/, es/)
  application.rb, environments/  # app + per-environment settings
db/
  migrate/       # versioned database changes
  schema.rb      # the current database structure (auto-generated)
test/            # the test suite
Gemfile          # the project's library (gem) dependencies
```

Convention again: a file's **location and name** tell Rails what it is.

## 1.4 Models & ActiveRecord (talking to the database)

A **model** is a Ruby class that represents one database table. Rails' ORM
(Object-Relational Mapper) is called **ActiveRecord**. It lets you write Ruby instead
of SQL:

```ruby
Track.where(title: "Karma Police").order(:position).first
# becomes: SELECT * FROM tracks WHERE title = 'Karma Police' ORDER BY position LIMIT 1
```

Models do four jobs (all visible in `app/models/`):

- **Associations** — how tables relate. `Album has_many :tracks`, `Track belongs_to :album`.
  → [Association Basics](https://guides.rubyonrails.org/association_basics.html)
- **Validations** — rules enforced before saving. `validates :title, presence: true`.
  → [Validations](https://guides.rubyonrails.org/active_record_validations.html)
- **Callbacks** — hooks at lifecycle points. `after_create :enqueue_context_generation`.
  → [Callbacks](https://guides.rubyonrails.org/active_record_callbacks.html)
- **Business methods** — e.g. `Album#average_rating`.

**Migrations** change the database over time. Each migration is a versioned file in
`db/migrate/`. You never edit `schema.rb` by hand — you write a migration and run
`bin/rails db:migrate`, which updates the schema. This keeps every developer's database
in sync and gives you a history of changes.
→ [Migrations](https://guides.rubyonrails.org/active_record_migrations.html)

## 1.5 Controllers & ActionController

Controllers are the **traffic cops**. A controller action (a method like `show`) should
be *thin*: authenticate, fetch data via the model, set instance variables, render.
Heavy logic belongs in the model or a service object (see §3.1).

Two things every Rails beginner must learn here:

- **Instance variables (`@track`) are the bridge** from controller to view. Anything you
  set in the action is visible in the template.
- **Strong Parameters** — you must explicitly allow which form fields can be saved.
  This stops an attacker from setting fields you didn't intend (mass-assignment).
  → [Strong Parameters](https://guides.rubyonrails.org/action_controller_overview.html#strong-parameters)

## 1.6 Views, ERB, and layouts

Views are `.html.erb` files: HTML with `<% ruby %>` (run code) and `<%= ruby %>`
(run code *and* print the result). Every page is wrapped in a shared **layout**
(`app/views/layouts/application.html.erb`) which holds the `<head>`, the sidebar, etc.,
and drops the page-specific content in with `<%= yield %>`.

**Partials** (files starting with `_`, e.g. `_search_results.html.erb`) are reusable
view fragments. → [Layouts and Rendering](https://guides.rubyonrails.org/layouts_and_rendering.html)

## 1.7 Routing

`config/routes.rb` maps URLs to controller actions. `resources :albums` is a shortcut
that generates the standard CRUD routes (index/show/new/create/edit/update/destroy)
following REST conventions. RESTful routing means URLs are predictable: a "thing" has a
consistent set of URLs. → [Routing](https://guides.rubyonrails.org/routing.html)

## 1.8 Hotwire: why there's no React here

Noted is interactive (live search, modals, inline follow buttons) but uses **no
front-end framework**. Instead it uses **Hotwire**, Rails' default approach:

- **Turbo Drive** intercepts link clicks/form submits and swaps page content without a
  full reload — fast navigation, no JS written by you.
- **Turbo Frames** mark a region of the page as independently updatable (the genre
  filter refreshes just the album grid).
- **Stimulus** is a tiny JS framework for sprinkling behaviour onto HTML via
  `data-controller` / `data-action` attributes (the Log Album modal, the avatar preview).

The philosophy: send **HTML over the wire** from the server, keep JavaScript minimal.
For a content site like this, that's far simpler than a React SPA.
→ [Turbo Handbook](https://turbo.hotwired.dev/handbook/introduction) ·
[Stimulus Handbook](https://stimulus.hotwired.dev/handbook/introduction)

JavaScript is delivered with **importmap** (no Node build step) — browsers load ES
modules directly. → [importmap-rails](https://github.com/rails/importmap-rails)

## 1.9 Gems and Bundler

A **gem** is a Ruby library. The `Gemfile` lists the project's gems; `bundle install`
installs them. Key gems in Noted: `devise` (login), `sidekiq` (background jobs),
`kaminari` (pagination), `httparty` (HTTP calls), `anthropic` (Claude AI),
`rails-i18n`/`devise-i18n` (translations), `tailwindcss-rails` (CSS).

## 1.10 Background jobs

Some work is too slow to do during a web request (calling an AI API can take seconds).
Rails' **Active Job** queues that work to run *later*, in a separate process. Noted uses
**Sidekiq** (backed by Redis) as the queue. Example: when you log an album, the page
responds instantly, and `AlbumContextJob` calls Claude in the background to write the
album's context card. → [Active Job Basics](https://guides.rubyonrails.org/active_job_basics.html)
· [Sidekiq](https://github.com/sidekiq/sidekiq)

---

# Part 2 — Noted, the application

## 2.1 What it is

**Noted is "Letterboxd for music"** — you log albums and tracks you've listened to, rate
and review them, follow other listeners, and get AI-generated taste profiles and
recommendations.

## 2.2 The data model (6 tables)

```
User ──< ListenLog >── Album ──< Track >── TrackLog >── User
  │                                                       
  └──< Follow >── User   (a user follows users; self-referential)
```

- **User** — account (Devise handles login). Has a username, optional name/bio/avatar.
- **Album** — a record/release. Created on demand from iTunes data.
- **Track** — a song on an album (`Track belongs_to :album`).
- **ListenLog** — a user's log of an **album** (rating, review, date). *Drives the AI taste profile.*
- **TrackLog** — a user's log of a single **track**. *Deliberately separate from the taste profile.*
- **Follow** — a directed "user A follows user B" relationship (a join table).

→ Full schema & methods: [Models doc](./models.md)

## 2.3 Core features

| Feature | How it works |
|---|---|
| **Log an album** | The sidebar modal searches iTunes live (Stimulus + `MusicController`), you pick a result, rate/review, submit → creates a `ListenLog`. |
| **Log a track** | Track pages have an inline log form → `TrackLog`. |
| **iTunes catalogue** | We don't store a music database; we fetch from the free Apple iTunes Search API on demand and persist albums/tracks the first time they're touched. |
| **AI taste profile** | Every 5th album log queues `TasteProfileJob`, which asks Claude to summarise your taste. |
| **AI album context** | New albums queue `AlbumContextJob` (a Claude-written blurb). |
| **Discover** | Natural-language recommendations from Claude, enriched with iTunes cover art. |
| **Follow / feed** | Follow users; your profile shows friends' recent activity. |
| **Genre filter** | The Albums page filters the community library by genre using stackable pills (server-side SQL filter inside a Turbo Frame). |
| **Internationalisation** | The whole UI is available in English and Spanish via URL (`/albums`, `/es/albums`). |

## 2.4 Design decisions worth understanding

- **Two separate log types (ListenLog vs TrackLog).** They look similar but are kept
  apart on purpose: only *album* logs feed the AI taste profile, so the signal stays
  clean. `TrackLog` intentionally has **no** taste-profile callback — and there's a test
  asserting that, so nobody adds one by accident.
- **iTunes as the catalogue.** Maintaining a music database is huge; instead we lazily
  import from iTunes and cache locally. First view hits iTunes, every view after hits our DB.
- **AI is always asynchronous** (except Discover). External API calls never block the
  page — they run in Sidekiq. This is the single biggest reason the app feels fast.

---

# Part 3 — Coding practices in this codebase, and why they're best practice

Each item: *what it is → the example here → why it's best practice → a link.*

## 3.1 Thin controllers, logic in models & service objects

**What:** Controllers stay short; complex logic lives elsewhere. Logic that doesn't
belong to a single model (like "call the iTunes API") goes in a **service object** — a
plain Ruby class in `app/services/` (e.g. `MusicSearchService`, `ClaudeService`).

**Why:** Fat controllers become untestable spaghetti. Pushing logic into models/services
makes it reusable and unit-testable in isolation (you can test `MusicSearchService`
without a web request — see `test/services/`). This is the widely-taught "skinny
controller" guideline. → [Action Controller Overview](https://guides.rubyonrails.org/action_controller_overview.html)

## 3.2 Preventing N+1 queries (the #1 Rails performance trap)

**What:** An "N+1" is when you load N records, then fire one extra query *per record* in a
loop. Example of the bug: showing 25 albums and calling `album.average_rating` inside the
loop → 1 query for albums + 25 for ratings.

**How we fix it here, two ways:**
- **Eager loading** with `includes` — load associated records up front:
  `@logs = @user.listen_logs.includes(:album)` loads all albums in *one* extra query.
  → [Eager Loading Associations](https://guides.rubyonrails.org/active_record_querying.html#eager-loading-associations)
- **Preload helpers** for aggregates — `preload_album_stats(albums)` runs *two grouped SQL
  queries* (`GROUP BY`) and returns `{album_id => {count, avg}}`, which the view looks up
  in O(1). We measured the albums grid going from **77 queries → 3**.

**Why:** N+1 is the classic "fast in development, falls over in production" problem — it
scales linearly with data and saturates the DB connection pool under load. The Rails guide
above is the canonical reference; the [Bullet gem](https://github.com/flyerhzm/bullet)
is the standard tool for detecting N+1s automatically.

## 3.3 Query in SQL, not in Ruby

**What:** Aggregations and filters are pushed to the database, not done by loading
everything and looping in Ruby. The genre filter is `Album.where(genre: @active_genres)`
(SQL `IN`), and ratings use `.group(:track_id).average(:rating)` (SQL `AVG` + `GROUP BY`).

**Why:** Databases are *built* for this and do it on indexed columns far faster than Ruby
can, and you transfer far less data into memory.
→ [Active Record Query Interface](https://guides.rubyonrails.org/active_record_querying.html)

## 3.4 Smart database indexes

**What:** An index is a lookup structure that makes `WHERE`/`ORDER BY`/`JOIN` on a column
fast (like a book's index vs reading every page). Noted indexes every foreign key, every
uniqueness constraint, plus hot query columns (`tracks.itunes_track_id` unique,
`albums.genre`, and composite `[user_id, listened_on]` for "this user's logs, newest first").

**Why:** Without an index the DB does a full-table "sequential scan." With one it jumps
straight to the rows. The composite index is the textbook **filter-and-sort** pattern.
Caveat we respect: on *tiny* tables Postgres ignores indexes (a scan is faster) — they're
"dormant infrastructure" that pays off at scale.
→ [PostgreSQL — Indexes](https://www.postgresql.org/docs/current/indexes.html)

## 3.5 Strong Parameters (mass-assignment protection)

**What:** `params.require(:listen_log).permit(:rating, :review, :listened_on, :is_relisten)`
— only those fields can be saved.

**Why:** Without it, a crafted request could set *any* column (e.g. someone else's
`user_id`). This is a real, historically-exploited vulnerability class.
→ [Strong Parameters](https://guides.rubyonrails.org/action_controller_overview.html#strong-parameters)
· [Securing Rails Applications](https://guides.rubyonrails.org/security.html)

## 3.6 Internationalisation (i18n) instead of hardcoded text

**What:** No user-facing string is hardcoded in a view. Instead `t("flash.albums.no_id")`
looks up text from `config/locales/{en,es}/*.yml`. Dates use `l(date, format: :noted_long)`.

**Why:** Adding a language becomes "drop in a new YAML file," not "edit 32 templates." It
also centralises copy and makes pluralisation correct across languages. We used the
`i18n-tasks` gem to verify zero missing/unused keys.
→ [Rails Internationalization (I18n)](https://guides.rubyonrails.org/i18n.html)

## 3.7 No inline JavaScript / strict Content Security Policy

**What:** Stimulus controllers hold **no hardcoded strings or `onclick=`**. Instead the
server passes data via `data-*-value` attributes (Stimulus "values"). This let us enable a
strict **Content Security Policy** with `script-src 'self'` + a per-request nonce — no
`'unsafe-inline'`.

**Why:** Inline scripts are the main vector for XSS (cross-site scripting). A strict CSP
that forbids inline scripts is one of the strongest XSS mitigations available.
→ [Rails Security — CSP](https://guides.rubyonrails.org/security.html#content-security-policy-header)
· [Stimulus Values](https://stimulus.hotwired.dev/reference/values)

## 3.8 RESTful, resourceful routes

**What:** `resources :track_logs, only: [:create, :edit, :update, :destroy]` generates
conventional URLs and route helpers (`edit_track_log_path(log)`).

**Why:** Predictable, conventional URLs are easier to reason about, and the named helpers
mean you never hardcode a URL string (so changing a route updates everywhere).
→ [Routing — Resourceful Routing](https://guides.rubyonrails.org/routing.html#resource-routing-the-rails-default)

## 3.9 Tests as a safety net

**What:** The app has model, controller/integration, and service tests (Minitest, in
`test/`). They assert real behaviour — e.g. that a duplicate log is rejected, that
`TrackLog` has *no* taste callback, and that pages render in both locales without missing
translations.

**Why:** Tests let you refactor fearlessly (we ran the full suite after every change in
the i18n and performance work). They're executable documentation of intended behaviour.
→ [Testing Rails Applications](https://guides.rubyonrails.org/testing.html)

## 3.10 Convention over Configuration, everywhere

Notice you've rarely seen config: a `TracksController` finds `app/views/tracks/`, a
`Track` model finds the `tracks` table, `track_path(t)` builds `/tracks/42`. Leaning on
conventions is itself the practice — fighting them creates surprise.
→ [The Rails Doctrine](https://rubyonrails.org/doctrine)

---

# Part 4 — Running it & where to look first

```bash
bundle install                 # install gems
bin/rails db:create db:migrate # set up the database
bundle exec sidekiq            # start the background-job worker (for AI)
bin/dev                        # start the app (or: bin/rails server)
```

Requirements: PostgreSQL and Redis running locally; `ANTHROPIC_API_KEY` in your env for AI
features (iTunes works without any key).

**A good reading order for your first hour:**
1. `config/routes.rb` — the map of every URL.
2. `app/controllers/tracks_controller.rb` — a small, representative controller.
3. `app/models/listen_log.rb` and `track_log.rb` — validations + the callback design.
4. `app/views/tracks/show.html.erb` — how a view uses `@variables` and `t()`.
5. `app/controllers/application_controller.rb` — the shared helpers (locale switching,
   `preload_track_ratings`, `preload_album_stats`) every page relies on.

**The single best external resource** is the official Rails Guides — start with
[Getting Started](https://guides.rubyonrails.org/getting_started.html), then read the
[Active Record](https://guides.rubyonrails.org/active_record_basics.html) and
[Action Controller](https://guides.rubyonrails.org/action_controller_overview.html) guides.
For day-to-day API lookups: [api.rubyonrails.org](https://api.rubyonrails.org).
