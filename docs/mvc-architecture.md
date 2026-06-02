# MVC Architecture in Noted

## What is MVC?

MVC (Model–View–Controller) is an architectural pattern that separates an application into three interconnected layers. Rails is built around this pattern.

```
Browser ──► Router ──► Controller ──► Model (database)
                           │
                           └──► View (HTML) ──► Browser
```

---

## The Three Layers

### Model
The Model layer manages data. In Rails every model is a Ruby class that inherits from `ActiveRecord::Base`. Models:
- Map to a database table (e.g. `Album` ↔ `albums` table)
- Express relationships between tables (`belongs_to`, `has_many`)
- Validate data before it's saved
- Encapsulate business logic that belongs to the data (e.g. `album.average_rating`)
- Fire callbacks at specific lifecycle points (`after_create`, etc.)

In Noted the core models are: `User`, `Album`, `Track`, `ListenLog`, `TrackLog`, `Follow`.

### View
The View layer is responsible only for presentation. In Rails, views are `.html.erb` files (HTML with embedded Ruby). They:
- Receive instance variables set by the controller (`@album`, `@logs`, etc.)
- Render HTML that the browser displays
- Never contain business logic or direct database queries

Noted also uses **partial templates** (files beginning with `_`) for reusable fragments, and `content_for`/`yield` to inject page-specific titles and head elements into the shared layout.

### Controller
The Controller layer is the traffic manager. It:
- Receives HTTP requests from the router
- Authenticates and authorises the current user
- Calls models to read or modify data
- Packages data into instance variables
- Tells Rails which view to render (or which URL to redirect to)

Controllers should be thin — complex logic belongs in the model or a service object.

---

## How a Request Flows Through Noted

Here is a concrete example: a user visits a track page at `GET /tracks/42`.

```
1. Browser sends:  GET /tracks/42

2. Rails router matches the path to:
      TracksController#show

3. ApplicationController#before_action fires:
      authenticate_user!  →  checks Devise session

4. TracksController#show executes:
      @track        = Track.includes(:album).find(42)   # Model query
      @album        = @track.album
      @album_tracks = @album.tracks.to_a
      @user_log     = current_user&.track_logs&.find_by(track: @track)
      @track_avg    = @track.average_rating              # Model method
      @track_ratings = preload_track_ratings(@album_tracks) # prevents N+1

5. Rails renders:  app/views/tracks/show.html.erb
   (wrapped in:    app/views/layouts/application.html.erb)

6. HTML is sent back to the browser.
```

---

## Hotwire: Turbo and Stimulus

Noted extends the standard request cycle with **Hotwire**, Rails' modern JavaScript layer.

### Turbo Drive
Turbo Drive intercepts link clicks and form submissions. Instead of doing a full browser page load it:
1. Fetches the new page via `fetch()`
2. Swaps only the `<body>` content
3. Updates the browser history with `pushState`

The result is fast navigation without a full JavaScript framework.

### Turbo Frames
Turbo Frames mark portions of a page as independently updatable. When a link or form inside a `<turbo-frame>` is activated, only the content of that frame is replaced — the surrounding page stays intact.

In Noted, `turbo_frame_tag "tracks-results"` wraps the track search results. Debounced search queries update only that region, not the whole page.

**Important:** links inside a Turbo Frame will try to update only the frame. To navigate the whole page from inside a frame, links must carry `data: { turbo_frame: "_top" }`.

### Stimulus
Stimulus is a modest JavaScript framework for attaching behaviour to HTML. Each Stimulus **controller** is a JavaScript class connected to a DOM element via `data-controller="name"`. It handles events (`data-action`) and references DOM nodes (`data-*-target`).

Noted uses Stimulus controllers for:

| Controller | Purpose |
|---|---|
| `log-flow` | Two-step Log Album modal (search → preview → submit) |
| `follows-modal` | Following/Followers pop-up (async fetch of user list) |
| `modal` | Generic backdrop open/close for the log modal |
| `search` | Debounced search input on the Tracks and Discover pages |
| `tabs` | Album/Track tab switcher on the Profile page |

---

## Services: Beyond MVC

Pure MVC sometimes isn't enough. Noted uses **service objects** for logic that doesn't belong in a model or controller:

| Service | Responsibility |
|---|---|
| `MusicSearchService` | Wraps all iTunes API calls; encapsulates HTTP, JSON parsing, field mapping |
| `ClaudeService` | Wraps all Anthropic API calls; builds prompts, calls the API, returns text |

Service objects are plain Ruby classes in `app/services/`. They have no database connection of their own.

---

## Background Jobs

Long-running operations (especially AI API calls) run outside the HTTP request cycle in **Sidekiq workers**:

| Job | Trigger | Does |
|---|---|---|
| `AlbumContextJob` | `Album.after_create` | Calls Claude to write a 2–3 sentence context card for the album |
| `TasteProfileJob` | Every 5th `ListenLog` saved | Calls Claude to regenerate the user's AI taste profile |
| `TrackImportJob` | `Album.after_create` (if iTunes ID present) | Calls iTunes to fetch and persist the album's full tracklist |

All AI jobs are queued on the `:ai` Sidekiq queue. `TrackImportJob` uses the `:default` queue.

---

## The Application Layout

`app/views/layouts/application.html.erb` is rendered around every page. It contains:

- The `<head>` (title, favicon, CSS, JS tags)
- The left sidebar (wordmark, navigation links, user avatar + name, sign-in/out)
- The main content area (`<%= yield %>`)
- The Log Album modal (hidden by default, shown by the `modal` Stimulus controller)
- Flash message overlays (auto-dismissed via CSS animation)

The sidebar is always visible; the main content scrolls independently.

---

## ApplicationController Responsibilities

`ApplicationController` is the parent class of every controller. Noted configures it to:

1. **Authenticate all requests** (`before_action :authenticate_user!`) except Devise's own sign-in/sign-up pages. This means every page requires a logged-in user unless the route is Devise-managed.

2. **Permit custom Devise fields** for sign-up (`:username`) and account updates (`:username`, `:bio`, `:favourite_genre`).

3. **Provide `preload_track_ratings`** — a private helper available to any controller that needs to show average track ratings without N+1 queries. It executes one `GROUP BY` + `AVG` SQL query and returns a `{ track_id => avg }` hash.

---

## Naming and File Conventions

Rails uses **Convention over Configuration**. Key conventions used in Noted:

| Thing | Convention | Example |
|---|---|---|
| Model | Singular CamelCase | `ListenLog` |
| Table | Plural snake_case | `listen_logs` |
| Controller | Plural CamelCase + `Controller` | `ListenLogsController` |
| View directory | Plural snake_case | `app/views/listen_logs/` |
| Route | `resources :listen_logs` generates standard CRUD paths | `GET /listen_logs/:id/edit` |
| Migration | Timestamp prefix | `20260529_create_track_logs.rb` |
