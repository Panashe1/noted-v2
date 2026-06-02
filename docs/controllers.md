# Controllers

This document covers every controller in Noted — its routes, actions, authentication rules, and business logic.

---

## Route map

```
GET    /                             → users#home
GET    /u/:username                  → users#show
GET    /u/:username/settings         → users#settings
PATCH  /u/:username/settings         → users#update_settings
POST   /u/:username/follow           → follows#create
DELETE /u/:username/follow           → follows#destroy
GET    /u/:username/following        → users#following
GET    /u/:username/followers        → users#followers
GET    /search                       → users#search

GET    /albums                       → albums#index
GET    /albums/:id                   → albums#show
GET    /albums/from_itunes           → albums#from_itunes

GET    /tracks                       → tracks#index
GET    /tracks/:id                   → tracks#show
GET    /tracks/from_itunes           → tracks#from_itunes

POST   /track_logs                   → track_logs#create
GET    /track_logs/:id/edit          → track_logs#edit
PATCH  /track_logs/:id               → track_logs#update
DELETE /track_logs/:id               → track_logs#destroy

POST   /listen_logs                  → listen_logs#create
GET    /listen_logs/:id/edit         → listen_logs#edit
PATCH  /listen_logs/:id              → listen_logs#update
DELETE /listen_logs/:id              → listen_logs#destroy
POST   /listen_logs/assist_review    → listen_logs#assist_review

GET    /discover                     → recommendations#index

GET    /music/search                 → music#search
GET    /music/preview                → music#preview
```

---

## ApplicationController

**File:** `app/controllers/application_controller.rb`

The parent class of every controller. Configures global behaviour.

### Before actions

| Before action | Condition | Effect |
|---|---|---|
| `authenticate_user!` | Unless `devise_controller?` | All routes require a signed-in user; Devise's own sign-in/sign-up pages are exempted. |
| `configure_permitted_parameters` | If `devise_controller?` | Whitelists extra Devise parameters (see below). |

### `configure_permitted_parameters`

Extends Devise's strong-parameter sanitiser:

```ruby
devise_parameter_sanitizer.permit(:sign_up,        keys: [:username])
devise_parameter_sanitizer.permit(:account_update, keys: [:username, :bio, :favourite_genre])
```

This is required because Devise's default allowlist only covers `email` and `password`. Without this, `username` would be stripped from sign-up params and never saved.

### `preload_track_ratings(tracks)` — private helper

Available to every subcontroller. Takes a collection or array of `Track` objects and returns a `{ track_id => Float }` hash of average ratings. Executes exactly **one** SQL `GROUP BY` + `AVG` query regardless of collection size.

```ruby
def preload_track_ratings(tracks)
  ids = Array(tracks).map(&:id)
  return {} if ids.empty?

  TrackLog.where(track_id: ids)
          .where.not(rating: nil)
          .group(:track_id)
          .average(:rating)
          .transform_values { |v| v.round(1) }
end
```

Usage in views: `@track_ratings[track.id]` — O(1) hash lookup.

---

## AlbumsController

**File:** `app/controllers/albums_controller.rb`

### Authentication

`before_action :authenticate_user!, only: [:from_itunes]`

`index` and `show` are publicly accessible (no login required). `from_itunes` requires authentication because it may create database records.

### `index`

**Route:** `GET /albums`

```ruby
@albums = Album.order(created_at: :desc).page(params[:page])
```

Fetches all albums in reverse-chronological order, paginated via Kaminari.

### `show`

**Route:** `GET /albums/:id`

```ruby
@album         = Album.find(params[:id])
@logs          = @album.listen_logs.includes(:user).order(created_at: :desc)
@user_log      = current_user&.listen_logs&.find_by(album: @album)
@album_tracks  = @album.tracks.to_a
@track_ratings = preload_track_ratings(@album_tracks)
```

Notable points:
- `includes(:user)` on `@logs` prevents N+1 when rendering user names/avatars on the community logs section.
- `@album.tracks.to_a` materialises the relation once — the array is passed to `preload_track_ratings` and also iterated in the view without additional queries.
- `current_user&.` safe navigation handles unauthenticated visitors (though in practice the global `authenticate_user!` means unauthenticated visitors are redirected before reaching this action).

### `from_itunes`

**Route:** `GET /albums/from_itunes?itunes_id=…`

Called when a user clicks an album from the Discover recommendations page. The album may or may not already exist in the local database.

**Flow:**

1. Validate that `itunes_id` is present; redirect back with alert if blank.
2. Check for an existing album via `Album.find_by(itunes_id: itunes_id)`.
3. If not found, call `MusicSearchService#fetch_album_with_tracks` to get data from iTunes.
4. If iTunes returns `nil` (album not found or network error), redirect back with alert.
5. Otherwise, `find_or_initialize_by(title:, artist:)` and `assign_attributes` + `save!`.
6. Redirect to `album_path(album)`.

Using `find_or_initialize_by(title:, artist:)` as a fallback (rather than purely on `itunes_id`) handles the edge case where the album was created manually (without an iTunes ID) before being matched via iTunes.

---

## TracksController

**File:** `app/controllers/tracks_controller.rb`

All actions inherit the global `authenticate_user!` from `ApplicationController`.

### `index`

**Route:** `GET /tracks` and `GET /tracks?q=…`

```ruby
@query = params[:q].to_s.strip
base   = Track.includes(:album).joins(:album)

if @query.length >= 2
  @tracks = base.where(
    "tracks.title ILIKE :q OR albums.title ILIKE :q OR albums.artist ILIKE :q",
    q: "%#{@query}%"
  ).order("albums.artist, albums.title, tracks.position").page(params[:page]).per(50)

  itunes_results  = MusicSearchService.new.search_tracks(@query)
  local_track_ids = Track.where(itunes_track_id: itunes_results.map { |t| t[:itunes_track_id] })
                         .pluck(:itunes_track_id).to_set
  @itunes_tracks  = itunes_results.reject { |t| local_track_ids.include?(t[:itunes_track_id]) }
else
  @tracks        = base.order("albums.artist, albums.title, tracks.position").page(params[:page]).per(50)
  @itunes_tracks = []
end

@track_ratings = preload_track_ratings(@tracks)
```

Key behaviour:
- Search requires at least 2 characters to avoid overwhelming the database and iTunes.
- `ILIKE` is case-insensitive PostgreSQL pattern matching.
- iTunes results are filtered to exclude tracks already in the local DB, preventing duplicate display.
- `preload_track_ratings` is called once at the end — ratings for all paginated tracks are loaded in a single query.

### `show`

**Route:** `GET /tracks/:id`

```ruby
@track        = Track.includes(:album).find(params[:id])
@album        = @track.album
@album_tracks = @album.tracks.to_a
@user_log     = current_user&.track_logs&.find_by(track: @track)
@track_avg    = @track.average_rating
@track_log_count = @track.log_count
@track_ratings   = preload_track_ratings(@album_tracks)
```

`@album_tracks` is materialised to an array so it can be passed to `preload_track_ratings` and reused in the sidebar tracklist without re-querying.

### `from_itunes`

**Route:** `GET /tracks/from_itunes?itunes_track_id=…&itunes_album_id=…`

Imports a track from iTunes if it doesn't already exist locally.

**Flow:**

1. Validate both params are present.
2. Check `Track.find_by(itunes_track_id:)` — if found, redirect immediately (no iTunes call needed).
3. Call `MusicSearchService#fetch_album_with_tracks(itunes_album_id)`.
4. Wrap album + track creation in an `ActiveRecord::Base.transaction` block:
   - Find existing album by `itunes_id`, or `find_or_initialize_by(title:, artist:)` and save.
   - Run `find_or_create_by(itunes_track_id:)` for **every** track in the iTunes response (idempotent; no `if album.tracks.none?` guard).
   - Return the specific track matching the requested `itunes_track_id`.
5. If found, redirect to `track_path(track)`. If the track wasn't in the response, redirect to `tracks_path` with a notice.

The transaction ensures no orphaned album record is left if track creation fails midway.

---

## UsersController

**File:** `app/controllers/users_controller.rb`

### Authentication

```ruby
before_action :authenticate_user!, only: [:home, :search, :settings, :update_settings]
before_action :require_own_profile, only: [:settings, :update_settings]
```

`show`, `following`, and `followers` are public (viewable without signing in).

### `home`

**Route:** `GET /` (root)

Redirects signed-in users to their own profile page. Because `authenticate_user!` is applied, unauthenticated visitors hitting the root are redirected to sign in.

```ruby
redirect_to user_path(current_user.username)
```

### `show`

**Route:** `GET /u/:username`

Loads the user's full profile data. The action branches on whether the viewer is looking at their own profile:

```ruby
@user = User.find_by!(username: params[:username])
@logs       = @user.listen_logs.includes(:album).order(listened_on: :desc)
@track_logs = @user.track_logs.includes(track: :album).order(listened_on: :desc)
@is_following = current_user&.following&.include?(@user) || false

if user_signed_in? && @user == current_user
  @own_profile    = true
  @recent_logs    = @logs.first(10)
  @following_logs = ListenLog.includes(:user, :album)
                             .where(user: current_user.following)
                             .order(created_at: :desc)
                             .limit(20)
  @taste_profile  = current_user.ai_taste_profile
end
```

`find_by!` raises `ActiveRecord::RecordNotFound` (→ 404) for unknown usernames.

`includes(:album)` on `@logs` and `includes(track: :album)` on `@track_logs` prevent N+1 when the view renders cover art and album/track metadata.

### `search`

**Route:** `GET /search?q=…`

```ruby
@query   = params[:q].to_s.strip
@results = if @query.length >= 2
  User.where("username ILIKE ?", "%#{@query}%")
      .where.not(id: current_user.id)
      .order(:username)
      .limit(20)
else
  User.none
end

respond_to do |format|
  format.html
  format.turbo_stream { render partial: "users/search_results", locals: { results: @results, query: @query } }
end
```

Excludes the current user from results. The Turbo Stream response renders only the partial, enabling inline partial-page updates without a full page load.

### `following` and `followers`

**Routes:** `GET /u/:username/following` and `GET /u/:username/followers`

Both actions:
1. Find `@user` by username.
2. Load `@list` (the following or followers list), ordered alphabetically.
3. Call `prep_follow_sets` to prepare `@my_following_ids` and `@my_follower_ids` as `Set` objects.
4. `render layout: false` — the response is an HTML fragment injected into the follows modal.

### `prep_follow_sets` (private)

```ruby
def prep_follow_sets
  if user_signed_in?
    @my_following_ids = current_user.following.pluck(:id).to_set
    @my_follower_ids  = current_user.followers.pluck(:id).to_set
  else
    @my_following_ids = Set.new
    @my_follower_ids  = Set.new
  end
end
```

Loads two sets in two queries. The `_follow_list` partial then does `@my_following_ids.include?(user.id)` (O(1)) to determine button state for each row, rather than querying per user.

### `settings`

**Route:** `GET /u/:username/settings`

Simply assigns `@user = current_user` and renders the settings form. `require_own_profile` ensures only the profile owner can access this page.

### `update_settings`

**Route:** `PATCH /u/:username/settings`

```ruby
@user = current_user
if @user.update(settings_params)
  redirect_to user_path(@user.username), notice: "Profile updated!"
else
  render :settings, status: :unprocessable_entity
end
```

On failure, re-renders the settings form with validation errors. Uses `422 Unprocessable Entity` status so that the browser history entry is not polluted with a successful-looking navigation.

### `require_own_profile` (private)

```ruby
def require_own_profile
  unless current_user.username == params[:username]
    redirect_to user_path(current_user.username), alert: "Not authorised."
  end
end
```

A secondary authorisation guard (in addition to `authenticate_user!`) preventing one user from editing another user's settings by guessing their URL.

### `settings_params` (private)

```ruby
params.require(:user).permit(:name, :bio, :avatar)
```

Whitelists only the fields that users may update through the settings form. `email` and `username` are intentionally excluded (username is read-only in the UI; email changes go through Devise's own flow).

---

## ListenLogsController

**File:** `app/controllers/listen_logs_controller.rb`

All actions require authentication (inherited from `ApplicationController`).

### Before actions

```ruby
before_action :set_log, only: [:edit, :update, :destroy]
```

`set_log` calls `current_user.listen_logs.find(params[:id])`. Scoping to `current_user` means a user trying to edit another user's log gets a `RecordNotFound` (→ 404) rather than a 403, which is the standard Rails pattern for not leaking information about whether a record exists.

### `create`

**Route:** `POST /listen_logs`

```ruby
@album = find_or_create_album
@log   = current_user.listen_logs.build(log_params.merge(album: @album))

if @log.save
  redirect_to album_path(@album), notice: "Logged!"
else
  redirect_back fallback_location: root_path, alert: @log.errors.full_messages.to_sentence
end
```

On failure, `redirect_back` returns the user to wherever they submitted from (the Log Album modal preserves the referrer in the header). `fallback_location: root_path` handles the rare case where no referrer is set.

### `find_or_create_album` (private)

```ruby
def find_or_create_album
  itunes_id = params[:album][:itunes_id].presence

  if itunes_id
    album = Album.find_by(itunes_id: itunes_id)
    return album if album
  end

  Album.find_or_create_by(
    title:  params[:album][:title].to_s.strip,
    artist: params[:album][:artist].to_s.strip
  ) do |a|
    a.release_year    = params[:album][:release_year].presence
    a.genre           = params[:album][:genre].presence
    a.cover_image_url = params[:album][:cover_image_url].presence
    a.itunes_id       = itunes_id
    a.apple_music_url = params[:album][:apple_music_url].presence
  end
end
```

Priority:
1. If an `itunes_id` is present and an album with that ID exists — use it directly.
2. Otherwise, `find_or_create_by(title:, artist:)` — handles both new albums and albums that were created manually and don't yet have an iTunes ID.

### `update`

**Route:** `PATCH /listen_logs/:id`

Updates the log's `rating`, `review`, `listened_on`, `is_relisten`. On success, redirects to the album page. On failure, re-renders `:edit` with `422`.

### `destroy`

**Route:** `DELETE /listen_logs/:id`

Destroys the log and `redirect_back`. Since `AlbumContextJob` and `TasteProfileJob` run asynchronously, destroying a log has no immediate AI side-effect (the taste profile is only regenerated on creation, not deletion).

### `assist_review`

**Route:** `POST /listen_logs/assist_review`

A JSON endpoint used by an "AI draft review" feature. Accepts `album_id`, `rating`, and optional `notes`, calls `ClaudeService#assist_review`, and returns `{ draft: "…" }`.

```ruby
render json: { draft: draft }
```

---

## TrackLogsController

**File:** `app/controllers/track_logs_controller.rb`

### Authentication

`before_action :authenticate_user!` — explicit (does not rely solely on inheritance, as a belt-and-suspenders clarification for the codebase reader).

### Before actions

```ruby
before_action :set_track_log, only: [:edit, :update, :destroy]
```

`set_track_log` scopes to `current_user.track_logs.find(params[:id])` — same ownership-enforcement pattern as `ListenLogsController`.

### `create`

```ruby
@track = Track.find_by(id: track_log_params[:track_id])
unless @track
  redirect_to tracks_path, alert: "Track not found." and return
end
@track_log = current_user.track_logs.new(track_log_params)

if @track_log.save
  redirect_to track_path(@track), notice: "Track logged!"
else
  redirect_to track_path(@track), alert: @track_log.errors.full_messages.first
end
```

Uses `find_by` (returns `nil`) instead of `find` (raises `RecordNotFound`) so a bad or missing `track_id` param produces a user-friendly redirect rather than a 500.

### `edit`

```ruby
@track = @track_log.track
```

Sets `@track` so the view can render a "back to track" link and form context.

### `update`

```ruby
@track = @track_log.track  # must be set before re-rendering :edit
if @track_log.update(track_log_params)
  redirect_to track_path(@track), notice: "Log updated!"
else
  render :edit, status: :unprocessable_entity
end
```

`@track` must be set before `render :edit` — the edit template references it to build the form action URL.

### `destroy`

```ruby
track = @track_log.track
@track_log.destroy
redirect_to track_path(track), notice: "Log removed."
```

Captures `track` before destroying (after destroy, `@track_log.track` may be nil due to the dependent relationship).

---

## FollowsController

**File:** `app/controllers/follows_controller.rb`

All actions require authentication (inherited).

### `create`

**Route:** `POST /u/:username/follow`

```ruby
user = User.find_by!(username: params[:username])
current_user.active_follows.find_or_create_by(following: user)
redirect_to user_path(user.username)
```

`find_or_create_by` is idempotent — clicking "Follow" on someone you already follow has no effect. The `Follow` model validates `cannot_follow_self`, so attempting to follow yourself raises a validation error (the route never renders such a button, but the defence is in the model).

### `destroy`

**Route:** `DELETE /u/:username/follow`

```ruby
user = User.find_by!(username: params[:username])
current_user.active_follows.find_by(following: user)&.destroy
redirect_to user_path(user.username)
```

`&.destroy` (safe navigation) means unfollowing someone you're not following is a no-op redirect rather than a 404.

---

## MusicController

**File:** `app/controllers/music_controller.rb`

AJAX endpoints consumed exclusively by the `log-flow` Stimulus controller inside the Log Album modal.

`before_action :authenticate_user!` — explicit.

Both actions `render layout: false` because they return HTML fragments, not full pages.

### `search`

**Route:** `GET /music/search?q=…`

```ruby
query    = params[:q].to_s.strip
@results = query.length >= 2 ? MusicSearchService.new.search_albums(query) : []
render layout: false
```

Returns an HTML fragment with a list of matching albums. The minimum query length of 2 prevents unnecessary iTunes API calls on every keystroke.

### `preview`

**Route:** `GET /music/preview?itunes_id=…`

```ruby
result = MusicSearchService.new.fetch_album_with_tracks(itunes_id)
if result.nil?
  render plain: "Album not found", status: :not_found
  return
end
@album_data = result[:album]
@tracks     = result[:tracks]
render layout: false
```

Returns an HTML fragment with album art, metadata, and tracklist for Step 2 of the log modal. Returns `404 Not Found` (plain text) if the iTunes lookup fails — the `log-flow` controller handles this gracefully.

---

## RecommendationsController

**File:** `app/controllers/recommendations_controller.rb`

Requires authentication (inherited).

### `index`

**Route:** `GET /discover?q=…`

```ruby
if @query.present?
  raw = ClaudeService.new.recommend(user: current_user, query: @query)
  @recommendations = enrich_with_itunes(parse_recommendations(raw))
else
  @recommendations = []
end
```

**`parse_recommendations(raw)`** — Claude is instructed to return JSON but sometimes wraps it in markdown code fences (` ```json … ``` `). This method strips those fences before parsing:

```ruby
json_str = raw.gsub(/\A```(?:json)?\s*/i, "").gsub(/\s*```\z/, "").strip
JSON.parse(json_str)
rescue JSON::ParserError => e
  Rails.logger.error("[RecommendationsController] JSON parse error: #{e.message}")
  []
```

**`enrich_with_itunes(recs)`** — For each recommendation Claude returns, performs a `search_albums` call to iTunes to obtain a `cover_url`, `itunes_id`, and confirm genre. The first result is used as "best match":

```ruby
recs.map do |rec|
  query   = "#{rec['artist']} #{rec['title']}"
  results = service.search_albums(query)
  best    = results.first
  rec.merge("itunes_id" => best&.dig(:itunes_id), "cover_url" => best&.dig(:cover_url), ...)
end
```

This is a synchronous loop of up to 5 iTunes calls (one per recommendation). If iTunes is slow or unavailable, the recommendations still appear but without cover art or an `itunes_id` link.
