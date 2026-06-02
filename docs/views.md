# Views

This document covers every page (view) in Noted — what it renders, what data it needs from the controller, and how user interactions work.

---

## Layout: `application.html.erb`

Every page in the application is wrapped in this layout. It is responsible for the global chrome that is always present on screen.

### Structure

```
┌─────────────────────────────────────────────┐
│  Sidebar (w-60, fixed width, full height)   │
│  ┌─────────────────────────────────────────┐│
│  │  "noted" wordmark                       ││
│  │  Navigation links                       ││
│  │  Log an album button (signed-in only)   ││
│  │  ─────────────────────────────────────  ││
│  │  User avatar + name + sign-out (bottom) ││
│  └─────────────────────────────────────────┘│
│  Main content area (flex-1, scrollable)     │
│  ┌─────────────────────────────────────────┐│
│  │  Flash messages (fixed, top-right)      ││
│  │  <%= yield %>                           ││
│  └─────────────────────────────────────────┘│
│  Log Album Modal (hidden by default)        │
└─────────────────────────────────────────────┘
```

### Navigation links

| Label | Route | Icon |
|---|---|---|
| Profile | `user_path(current_user.username)` or `root_path` if signed out | Person silhouette |
| Find People | `user_search_path` | Person + magnifier |
| Discover | `recommendations_path` | Magnifier |
| Albums | `albums_path` | Vinyl record |
| Tracks | `tracks_path` | Music note |

### Sidebar bottom section

- **Signed in:** Shows the user's avatar (Active Storage image if attached, otherwise a gradient-initials circle) alongside their display name / username and a sign-out icon button.
- **Signed out:** Shows Sign up (white pill) and Log in (plain text) buttons.

### Flash messages

Two types are supported:
- **Notice** — green (`bg-sp-green`) with a checkmark icon.
- **Alert** — red (`bg-red-500`).

Both are `fixed` at `top-4 right-4`, layered above content (`z-40`), and auto-dismissed via a CSS `flash-message` keyframe animation (no JavaScript required).

### Log Album Modal

The modal is always present in the DOM but hidden. It is controlled by two Stimulus controllers working together:

- **`modal`** — attached to `<body>`. Listens for `click->modal#open` (the "Log an album" sidebar button) and `click->modal#closeBtn` (the ✕ button and backdrop). Toggles `hidden` / `flex` on the panel.
- **`log-flow`** — attached to the modal card. Manages the two-step flow:

#### Step 1 — Search

An `<input>` fires `input->log-flow#onSearchInput` on each keystroke. The controller debounces the input and fetches `/music/search?q=…` (the `MusicController#search` endpoint). Results are injected as HTML into the `searchResults` target div. Each result row has a click handler that advances to Step 2.

A "Enter details by hand" fallback link calls `log-flow#showManual`, which skips the search step and renders a blank manual-entry form.

#### Step 2 — Preview + Log Form

After a result is clicked, the controller fetches `/music/preview?itunes_id=…` (`MusicController#preview`). The response contains album art, title, and tracklist which are injected into the `previewArea` target. Hidden `<input>` fields (`formTitle`, `formArtist`, etc.) are populated with the album's metadata.

The visible form fields are:

| Field | Type | Required |
|---|---|---|
| Date listened | `<input type="date">` | Yes |
| Relisten? | Checkbox | No |
| Rating | Radio group 1–10 | Yes (model validates) |
| Review | Textarea | No |

On submit, the form `POST`s to `listen_logs_path`.

---

## Authentication Pages (Devise)

### Sign in — `devise/sessions/new.html.erb`

**Route:** `GET /users/sign_in`

A centred card on a dark background. Contains:
- "noted" wordmark (large, letter-spaced)
- "Log in to continue" subtitle
- Email and password fields
- "Sign in" submit button
- Links to sign up and reset password

No instance variables beyond what Devise provides.

### Sign up — `devise/registrations/new.html.erb`

**Route:** `GET /users/sign_up`

Same layout as sign in. Contains:
- "noted" wordmark
- "Create your free account" subtitle
- Username field (required, validated: lowercase letters/numbers/underscores only)
- Email field
- Password and password confirmation fields
- "Create account" submit button
- Link back to sign in

### Reset password — `devise/passwords/new.html.erb`

**Route:** `GET /users/password/new`

Simple form with an email field. Submitting sends a password-reset email.

### Edit password — `devise/passwords/edit.html.erb`

**Route:** `GET /users/password/edit?reset_password_token=…`

Form for entering a new password + confirmation. Token is passed as a hidden field.

---

## Profile Page — `users/show.html.erb`

**Route:** `GET /u/:username`  
**Controller:** `UsersController#show`

### Instance variables

| Variable | Contents |
|---|---|
| `@user` | The `User` record for `:username` |
| `@logs` | All `ListenLog` records for this user, includes `:album`, ordered `listened_on: :desc` |
| `@track_logs` | All `TrackLog` records for this user, includes `track: :album`, ordered `listened_on: :desc` |
| `@is_following` | Boolean — whether `current_user` follows `@user` |
| `@own_profile` | `true` if viewing your own profile |
| `@recent_logs` | First 10 `@logs` (own profile only) |
| `@following_logs` | Up to 20 most-recent logs from people you follow (own profile only) |
| `@taste_profile` | `current_user.ai_taste_profile` string (own profile only) |

### Hero section

- **Avatar** — Active Storage image at `w-28 h-28` if attached; otherwise a gradient-initials circle (letter = first char of username, uppercased).
- **Name / username** — If `@user.name.present?`, the display name is the `<h1>` and `@username` appears as a muted subtitle. Otherwise `@username` is the headline directly.
- **Stats row** — Log count, following count (opens following modal), followers count (opens followers modal).
- **Bio** — Shown in muted text if `@user.bio.present?`, truncated at 2 lines.
- **Actions (right side):**
  - Own profile → gear icon linking to `user_settings_path`
  - Other profile (signed in) → Follow / Following button wrapped in `turbo_frame_tag "follow_#{@user.id}"` so toggling follow state updates inline without a full-page reload

### Follows modal

The `follows-modal` Stimulus controller intercepts clicks on the "following" and "followers" stat buttons. Each button carries `data-url` (the endpoint to fetch) and `data-title`. The controller:
1. Opens the modal panel and sets the title.
2. Fetches the URL (which renders a no-layout partial).
3. Injects the HTML into the scrollable content area.

The endpoints `users#following` and `users#followers` render `users/following.html.erb` and `users/followers.html.erb` respectively (both `render layout: false`). They share the `users/_follow_list.html.erb` partial.

### AI taste profile

Rendered as a left-bordered card above the logs section when `taste` is present. Shows the AI-generated paragraph about the user's listening patterns.

### Own-profile-only sections

#### Recently logged

A responsive grid of up to 10 album cards, each showing:
- Album art (or gradient fallback)
- Rating badge (bottom-left of art)
- Album title and artist

Clicking a card navigates to the album's show page.

#### Friends activity

A feed of up to 20 logs from people the user follows, showing album art, album + artist + follower name, and their rating. Ordered by creation time (most recent first).

### Logs section — Albums / Tracks tabs

Controlled by the `tabs` Stimulus controller. Two panels share the same tab UI:

- **Albums panel** — Numbered list of all album logs showing: position index, cover art, album title + artist + truncated review, rating, and log date.
- **Tracks panel** — Same format but for track logs; rating shows `—` if `nil`.

Both panels include empty-state messages for logged-in users vs. visitors.

---

## Profile Settings — `users/settings.html.erb`

**Route:** `GET /u/:username/settings`  
**Controller:** `UsersController#settings`  
**Access:** Own profile only (enforced by `require_own_profile` before action)

### Instance variables

| Variable | Contents |
|---|---|
| `@user` | `current_user` |

### Form

`form_with model: @user, url: user_settings_path, method: :patch, multipart: true`

| Field | Type | Notes |
|---|---|---|
| Avatar | `file_field :avatar` | Inline JS preview via `URL.createObjectURL`. Accepts `image/*`. |
| Display name | `text_field :name` | Max 60 chars, optional. |
| Bio | `text_area :bio` | Max 300 chars, optional. |
| Username | Read-only `<p>` | Not editable here. |

**Avatar preview** — An `onchange` handler on the file input calls `URL.createObjectURL(this.files[0])` and sets it as the `src` of a preview `<img>`. If the user had no avatar previously, the gradient-initials placeholder is hidden when a file is selected.

**Validation errors** — Displayed in a red card above the submit button if `@user.errors.any?`. Rendered on `status: :unprocessable_entity` (re-renders the form without a redirect).

---

## Albums Index — `albums/index.html.erb`

**Route:** `GET /albums`  
**Controller:** `AlbumsController#index`

### Instance variables

| Variable | Contents |
|---|---|
| `@albums` | Paginated `Album` records, ordered `created_at: :desc` |

Displays a grid of album cards. Each card shows the cover art (or a gradient fallback), the album title, artist, and year. Clicking navigates to `album_path(album)`.

Pagination links appear at the bottom (provided by Kaminari).

---

## Album Show — `albums/show.html.erb`

**Route:** `GET /albums/:id`  
**Controller:** `AlbumsController#show`

### Instance variables

| Variable | Contents |
|---|---|
| `@album` | The `Album` record |
| `@logs` | All `ListenLog` records for this album, includes `:user`, ordered `created_at: :desc` |
| `@user_log` | The current user's own `ListenLog` for this album (or `nil`) |
| `@album_tracks` | All tracks for this album as an array (prevents N+1) |
| `@track_ratings` | `{ track_id => avg_rating }` hash from `preload_track_ratings` |

### Sections

**Hero** — Large album art, album title, artist, year, genre, Apple Music link. Shows average rating + log count if any logs exist.

**AI context card** — If `@album.ai_context.present?`, a bordered card with the AI-generated 2–3 sentence context blurb.

**Tracklist** — Ordered by `tracks.position`. Each row shows the track's position number, title, average rating badge (from `@track_ratings`), and formatted duration. Clicking a track navigates to `track_path(track)`.

**Your log / Log this album** — If `@user_log` exists, shows the user's rating, review, and date with edit/delete links. If not, shows the "Log this album" button which opens the Log Album modal (via `click->modal#open`).

**Community logs** — List of other users' logs for this album showing avatar, username, rating, and truncated review.

---

## Tracks Index — `tracks/index.html.erb`

**Route:** `GET /tracks` (and `GET /tracks?q=…`)  
**Controller:** `TracksController#index`

### Instance variables

| Variable | Contents |
|---|---|
| `@query` | The search string from `params[:q]` |
| `@tracks` | Paginated local tracks (filtered by query if `q.length >= 2`) |
| `@itunes_tracks` | iTunes search results that are NOT already in the local DB |
| `@track_ratings` | `{ track_id => avg_rating }` hash for `@tracks` |

### Search behaviour

The search input is controlled by the `search` Stimulus controller, which debounces keystrokes. The request targets a `turbo_frame_tag "tracks-results"` wrapping the results section, so only that region is replaced — the page header and search bar remain.

### Columns

`grid-cols-[2rem_1fr_auto_auto_auto]` — Index, Track + Album, Avg rating, Duration, (iTunes indicator for iTunes results).

**Local tracks** show the average rating from `@track_ratings` coloured by score (green for high, amber for mid, red for low, muted grey for no data). Track names link to `track_path`.

**iTunes results** (shown below a divider) display results not yet in the local DB. They carry a "From iTunes" badge and link to `from_itunes_tracks_path` with the relevant IDs — clicking imports the album and redirects to the track page.

---

## Track Show — `tracks/show.html.erb`

**Route:** `GET /tracks/:id`  
**Controller:** `TracksController#show`

### Instance variables

| Variable | Contents |
|---|---|
| `@track` | The `Track` record, includes `:album` |
| `@album` | `@track.album` |
| `@album_tracks` | All tracks on the album (array) |
| `@user_log` | The current user's `TrackLog` for this track (or `nil`) |
| `@track_avg` | Float or nil — average rating across all track logs |
| `@track_log_count` | Integer — total log count |
| `@track_ratings` | `{ track_id => avg_rating }` hash for the full album tracklist |

### Layout

Two-column layout on larger screens:

**Left — Main content**

- **Hero** — Track title, album artist name, album title (links to album page). Metadata row: position, duration, average rating, log count.
- **Your log section** — If `@user_log` exists, shows the user's rating + review + date with edit and delete links. Otherwise shows a "Log this track" form (date, optional rating, optional review, relisten checkbox).
- **Community logs** — Other users' track logs with avatar, username, rating, review.

**Right — Sidebar**

- Album art (links to album page).
- Full tracklist with per-track average badges from `@track_ratings`. The current track is highlighted. Other tracks link to their own show pages.

---

## Discover — `recommendations/index.html.erb`

**Route:** `GET /discover` (and `GET /discover?q=…`)  
**Controller:** `RecommendationsController#index`

### Instance variables

| Variable | Contents |
|---|---|
| `@query` | The natural-language search query |
| `@recommendations` | Array of enriched recommendation hashes (or `[]`) |

### Idle state

When `@query` is blank, shows a set of example prompt chips. Clicking one populates the search bar and submits the form, navigating to `?q=…`.

### Results state

Each recommendation is rendered as a card showing:
- Album art (iTunes cover URL, downsized to 160px for display)
- Title + artist + year
- Claude's one-sentence description

If `rec["itunes_id"]` is present, the card links to `from_itunes_albums_path(itunes_id: …)` which find-or-creates the album and redirects to its show page.

If Claude couldn't be reached or returns no data, an error message is shown instead of a results list.

---

## Find People — `users/search.html.erb`

**Route:** `GET /search`  
**Controller:** `UsersController#search`

### Instance variables

| Variable | Contents |
|---|---|
| `@query` | Search string |
| `@results` | `ActiveRecord::Relation` of matching users (or `User.none`) |

### Behaviour

A search input (controlled by the `search` Stimulus controller with debounce) targets `turbo_frame_tag "user-search-results"`. Queries of fewer than 2 characters return no results. Matches on `username ILIKE ?`, excludes the current user.

Results are rendered via `users/_search_results.html.erb` — each row shows the user's avatar / initials, username, log count, and a Follow / Following button.

Turbo Stream requests render just the partial; regular HTML requests render the full page (for direct navigation or non-JS fallback).

---

## Listen Log Edit — `listen_logs/edit.html.erb`

**Route:** `GET /listen_logs/:id/edit`  
**Controller:** `ListenLogsController#edit`

Renders a form pre-filled with the existing log's data (rating, review, listened_on, is_relisten). On submit, `PATCH /listen_logs/:id`. On success, redirects to the album page.

---

## Track Log Edit — `track_logs/edit.html.erb`

**Route:** `GET /track_logs/:id/edit`  
**Controller:** `TrackLogsController#edit`

Same pattern as the listen log edit. Pre-fills rating (optional), review, listened_on, and is_relisten. On submit, `PATCH /track_logs/:id`. On success, redirects to the track page.

---

## Music Search / Preview (Modal AJAX endpoints)

These views are rendered without the application layout (`render layout: false`) and are only consumed by the `log-flow` Stimulus controller inside the modal.

### `music/search.html.erb`

**Route:** `GET /music/search?q=…`  
**Returns:** HTML fragment — a list of matching album rows.

Each row includes: a small cover thumbnail, album title, artist, and year. Clicking triggers Step 2 in the log-flow controller.

### `music/preview.html.erb`

**Route:** `GET /music/preview?itunes_id=…`  
**Returns:** HTML fragment — album art, title, tracklist.

Instance variables: `@album_data` (hash from iTunes), `@tracks` (array of track hashes). The preview is injected into the `previewArea` target of the `log-flow` controller. Hidden form fields are populated from `@album_data` by the controller's JavaScript.

---

## Partials

| Partial | Used by | Purpose |
|---|---|---|
| `users/_follow_list.html.erb` | `users/following`, `users/followers` | Renders a scrollable list of users with follow/unfollow buttons |
| `users/_search_results.html.erb` | `users/search` (Turbo Stream) | User search result rows for the Find People page |
| `devise/shared/_error_messages.html.erb` | Devise forms | Renders model validation errors above Devise forms |
| `devise/shared/_links.html.erb` | Devise forms | Renders sign-in / sign-up / forgot-password navigation links |
