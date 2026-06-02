# Models

This document covers every model in Noted — its database columns, associations, validations, callbacks, scopes, and key instance methods.

---

## Database schema overview

```
users ──────────────┬── listen_logs ──── albums ──── tracks ──── track_logs ──── users
                    │                                                             │
                    └── track_logs ────────────────────────────────────────────-┘
                    │
                    ├── active_follows  (follows.follower_id)
                    └── passive_follows (follows.following_id)
```

### Key design decisions

- **Two separate log types.** Albums are logged via `ListenLog`; individual tracks via `TrackLog`. They are entirely independent tables with no foreign-key relationship to each other. `TrackLog` deliberately has no `after_create` callback — track logs do not affect the AI taste profile.
- **Albums are created on demand.** Albums are not pre-seeded. They are created the first time a user logs them (via `ListenLogsController#find_or_create_album`) or when they are imported from iTunes (via `AlbumsController#from_itunes`).
- **AI fields are nullable.** `albums.ai_context` and `users.ai_taste_profile` are populated by background jobs. They start `NULL` and may remain so if the job hasn't run or if the Claude API is unavailable.

---

## ApplicationRecord

**File:** `app/models/application_record.rb`

The abstract base class for all models. Inherits from `ActiveRecord::Base` with `self.abstract_class = true`. Every model in Noted inherits from this class rather than directly from `ActiveRecord::Base`, following Rails convention.

---

## User

**File:** `app/models/user.rb`

### Columns

| Column | Type | Notes |
|---|---|---|
| `id` | integer | Primary key |
| `username` | string | Unique, case-insensitive, `[a-z0-9_]+` only |
| `email` | string | Managed by Devise |
| `encrypted_password` | string | bcrypt hash, managed by Devise |
| `name` | string | Optional display name (max 60 chars) |
| `bio` | text | Optional profile bio (max 300 chars) |
| `ai_taste_profile` | text | AI-generated taste description, set by `TasteProfileJob` |
| `taste_profile_generated_at` | datetime | Timestamp of last taste-profile generation |
| `favourite_genre` | string | Optionally editable via Devise account update |
| `reset_password_token` | string | Devise |
| `reset_password_sent_at` | datetime | Devise |
| `remember_created_at` | datetime | Devise |
| `created_at` | datetime | |
| `updated_at` | datetime | |

### Devise modules

```ruby
devise :database_authenticatable, :registerable,
       :recoverable, :rememberable, :validatable
```

| Module | Provides |
|---|---|
| `database_authenticatable` | Password hashing + email/password sign-in |
| `registerable` | Sign-up and account deletion |
| `recoverable` | Password-reset emails |
| `rememberable` | "Remember me" persistent session cookie |
| `validatable` | Validates presence + format of email, presence + minimum length of password |

### Active Storage

```ruby
has_one_attached :avatar
```

Stores profile pictures via Active Storage. In development, files are saved to `storage/` on local disk (configured in `config/storage.yml`). In production, a cloud adapter (e.g., S3) would be configured.

### Associations

```ruby
has_many :listen_logs,  dependent: :destroy
has_many :albums,       through: :listen_logs

has_many :track_logs,   dependent: :destroy

has_many :active_follows,  class_name: "Follow", foreign_key: :follower_id,  dependent: :destroy
has_many :passive_follows, class_name: "Follow", foreign_key: :following_id, dependent: :destroy
has_many :following, through: :active_follows,  source: :following
has_many :followers, through: :passive_follows, source: :follower
```

The follow system uses two named join associations on the same `follows` table:
- `active_follows` — rows where this user is the **follower** (who they follow)
- `passive_follows` — rows where this user is being **followed** (who follows them)

`has_many :following` and `has_many :followers` are the usable end associations. Both use `dependent: :destroy` on their join model so that deleting a user cleans up all follow relationships.

### Validations

| Validation | Rule |
|---|---|
| `username` | Required, unique (case-insensitive), format: `/\A[a-z0-9_]+\z/` |
| `name` | Optional; max 60 characters |
| `bio` | Optional; max 300 characters |
| `avatar` (custom) | If attached, content type must be `image/jpeg`, `image/png`, `image/gif`, or `image/webp` |
| Email, password | Validated by Devise's `validatable` module |

### Custom validation

```ruby
def avatar_content_type
  return unless avatar.attached?
  unless avatar.content_type.in?(%w[image/jpeg image/png image/gif image/webp])
    errors.add(:avatar, "must be a JPEG, PNG, GIF, or WebP image")
  end
end
```

This runs on every save where an avatar is attached. It prevents users from uploading SVGs, PDFs, or other non-image files.

### Instance methods

#### `regenerate_taste_profile!`

```ruby
def regenerate_taste_profile!
  TasteProfileJob.perform_later(id)
end
```

Enqueues a background job to rebuild the AI taste profile. Called by `ListenLog#maybe_regenerate_taste_profile` every fifth album log.

#### `logged?(album)`

```ruby
def logged?(album)
  listen_logs.exists?(album: album)
end
```

Returns `true` if this user has a `ListenLog` for the given album. Uses `EXISTS` in SQL — more efficient than loading the log.

#### `average_rating`

```ruby
def average_rating
  listen_logs.average(:rating)&.round(1)
end
```

Returns the user's average album rating across all their listen logs, rounded to 1 decimal place. Returns `nil` if they have no logs.

---

## Album

**File:** `app/models/album.rb`

### Columns

| Column | Type | Notes |
|---|---|---|
| `id` | integer | Primary key |
| `title` | string | Required |
| `artist` | string | Required |
| `release_year` | integer | From iTunes or manual entry |
| `genre` | string | From iTunes |
| `cover_image_url` | string | iTunes artwork URL (100×100); upscaled by `cover_url()` |
| `itunes_id` | string | iTunes `collectionId`; unique per album in iTunes |
| `apple_music_url` | string | Deep link to Apple Music |
| `ai_context` | text | AI-generated 2–3 sentence context card (set by `AlbumContextJob`) |
| `ai_context_generated_at` | datetime | Timestamp of last AI context generation |
| `created_at` | datetime | |
| `updated_at` | datetime | |

### Associations

```ruby
has_many :listen_logs, dependent: :destroy
has_many :listeners,   through: :listen_logs, source: :user
has_many :tracks,      dependent: :destroy
```

`has_many :listeners` provides `album.listeners` — the set of users who have logged this album.

`dependent: :destroy` on both `listen_logs` and `tracks` means deleting an album cascades to all its logs and tracks. This preserves referential integrity (no orphaned foreign keys).

### Validations

```ruby
validates :title,  presence: true
validates :artist, presence: true
```

Both are required. No uniqueness constraint is enforced at the model level (only at the `find_or_create_by(title:, artist:)` call site), which allows edge cases like an artist releasing two albums with the same name.

### Callbacks

```ruby
after_create :enqueue_context_generation
after_create :enqueue_track_import, if: :itunes_id?
```

Both fire asynchronously — they enqueue Sidekiq jobs and return immediately, so the `Album#save!` call in the controller completes without waiting for the AI or iTunes response.

- **`enqueue_context_generation`** — always fires; queues `AlbumContextJob` on the `:ai` queue.
- **`enqueue_track_import`** — only fires when `itunes_id?` is truthy (i.e., the album came from iTunes); queues `TrackImportJob` on the `:default` queue.

### Instance methods

#### `average_rating`

```ruby
def average_rating
  listen_logs.average(:rating)&.round(1)
end
```

Average rating across all listen logs for this album, rounded to 1 dp. Returns `nil` with no logs.

#### `log_count`

```ruby
def log_count
  listen_logs.count
end
```

Total number of times this album has been logged by any user.

#### `cover_url(size: 600)`

```ruby
def cover_url(size: 600)
  return nil unless cover_image_url.present?
  cover_image_url.gsub(/\d+x\d+bb/, "#{size}x#{size}bb")
end
```

iTunes artwork URLs follow the pattern `…/100x100bb.jpg`. This method substitutes the dimensions to request a larger version. The default of 600 is used for album art on show pages; smaller values (60, 160, 300) are passed by views for thumbnails.

---

## Track

**File:** `app/models/track.rb`

### Columns

| Column | Type | Notes |
|---|---|---|
| `id` | integer | Primary key |
| `album_id` | integer | Foreign key → `albums.id` |
| `title` | string | Required |
| `position` | integer | Track number within the album |
| `duration_ms` | integer | Duration in milliseconds (from iTunes) |
| `itunes_track_id` | string | iTunes `trackId` |
| `created_at` | datetime | |
| `updated_at` | datetime | |

### Associations

```ruby
belongs_to :album
has_many   :track_logs, dependent: :destroy
```

### Validations

```ruby
validates :title, presence: true
```

### Default scope

```ruby
default_scope { order(:position) }
```

Tracks are always returned in tracklist order. This means `album.tracks` is automatically sorted by track number without explicit `order` calls in controllers or views.

> **Note:** A `default_scope` affects all queries on this model including joins and aggregations. If a query requires a different ordering (e.g., sorting by average rating), it must call `.reorder(...)` to override.

### Instance methods

#### `average_rating`

```ruby
def average_rating
  track_logs.where.not(rating: nil).average(:rating)&.round(1)
end
```

Filters out logs without ratings (since rating is optional on `TrackLog`) before averaging.

#### `log_count`

```ruby
def log_count
  track_logs.count
end
```

Total log count regardless of whether a rating was given.

#### `duration_formatted`

```ruby
def duration_formatted
  return nil unless duration_ms&.positive?
  total_seconds = duration_ms / 1000
  minutes = total_seconds / 60
  seconds = total_seconds % 60
  format("%d:%02d", minutes, seconds)
end
```

Formats milliseconds as `"M:SS"` (e.g., `"3:45"`). Returns `nil` if `duration_ms` is nil or zero.

---

## ListenLog

**File:** `app/models/listen_log.rb`

Records a user logging an album. Each user can log each album at most once (enforced by a uniqueness validation), but may mark a log as a relisten.

### Columns

| Column | Type | Notes |
|---|---|---|
| `id` | integer | Primary key |
| `user_id` | integer | Foreign key → `users.id` |
| `album_id` | integer | Foreign key → `albums.id` |
| `rating` | integer | 1–10; required |
| `review` | text | Optional free-text review |
| `listened_on` | date | Date the album was listened to; required |
| `is_relisten` | boolean | Whether this is a repeat listen |
| `created_at` | datetime | |
| `updated_at` | datetime | |

### Associations

```ruby
belongs_to :user
belongs_to :album
```

Both associations are required by default (Rails 5+ `belongs_to` adds a presence validation automatically).

### Validations

```ruby
validates :rating,      presence: true, inclusion: { in: 1..10 }
validates :listened_on, presence: true
validates :user_id, uniqueness: {
  scope: :album_id,
  message: "you've already logged this album — edit your existing entry instead"
}
```

The composite uniqueness constraint on `(user_id, album_id)` enforces the one-log-per-album-per-user rule. The custom message is surfaced directly in the UI via `@log.errors.full_messages.to_sentence`.

### Callbacks

```ruby
after_create :maybe_regenerate_taste_profile
```

```ruby
def maybe_regenerate_taste_profile
  if user.listen_logs.count % 5 == 0
    user.regenerate_taste_profile!
  end
end
```

After every 5th album log, the user's AI taste profile is regenerated asynchronously. The modulo check means profiles are regenerated at log counts 5, 10, 15, 20, …

> **Important:** This callback fires on `after_create` only — not on `after_update` or `after_destroy`. Rating changes or log deletions do not trigger a regeneration.

---

## TrackLog

**File:** `app/models/track_log.rb`

Records a user logging an individual track. Structurally similar to `ListenLog` but **intentionally decoupled** from the AI taste system.

### Columns

| Column | Type | Notes |
|---|---|---|
| `id` | integer | Primary key |
| `user_id` | integer | Foreign key → `users.id` |
| `track_id` | integer | Foreign key → `tracks.id` |
| `rating` | integer | 1–10; optional (may be `nil`) |
| `review` | text | Optional |
| `listened_on` | date | Required |
| `is_relisten` | boolean | |
| `created_at` | datetime | |
| `updated_at` | datetime | |

### Key difference from `ListenLog`

`rating` is **optional** on `TrackLog` (validated with `allow_nil: true`). The rationale: users may want to log that they listened to a track without committing to a rating.

### Associations

```ruby
belongs_to :user
belongs_to :track
```

### Validations

```ruby
validates :listened_on, presence: true
validates :rating, numericality: { in: 1..10, only_integer: true }, allow_nil: true
validates :user_id, uniqueness: {
  scope: :track_id,
  message: "you've already logged this track — edit your existing entry instead"
}
```

### No taste-profile callback

`TrackLog` has **no `after_create` callback**. This is intentional and tested explicitly. Track logs are isolated from the taste-profile system, which is driven solely by album logs. The comment in the model source makes this explicit:

```ruby
# Intentionally no after_create taste-profile callback —
# track logs are separate from the album-based taste system.
```

---

## Follow

**File:** `app/models/follow.rb`

A join table representing a directed follow relationship between two users.

### Columns

| Column | Type | Notes |
|---|---|---|
| `id` | integer | Primary key |
| `follower_id` | integer | Foreign key → `users.id` (the person doing the following) |
| `following_id` | integer | Foreign key → `users.id` (the person being followed) |
| `created_at` | datetime | |
| `updated_at` | datetime | |

### Associations

```ruby
belongs_to :follower,  class_name: "User"
belongs_to :following, class_name: "User"
```

Both association names are non-standard (neither is `user`), so `class_name: "User"` is required for Rails to resolve the model. The names mirror the naming on the `User` model:

```
User.active_follows  →  Follow (follower_id = user.id)
User.passive_follows →  Follow (following_id = user.id)
User.following       →  Users followed by this user (through active_follows)
User.followers       →  Users who follow this user (through passive_follows)
```

### Validations

```ruby
validates :follower_id, uniqueness: { scope: :following_id }
validate  :cannot_follow_self
```

**Uniqueness** prevents duplicate follow rows. Combined with `find_or_create_by` in `FollowsController#create`, this means clicking "Follow" multiple times is safe.

**`cannot_follow_self`:**

```ruby
def cannot_follow_self
  errors.add(:base, "You can't follow yourself") if follower_id == following_id
end
```

A model-level guard that prevents `follower_id == following_id`. The UI never renders a Follow button on your own profile (`@own_profile` check in the view), but this defence lives in the model as a last line of protection.
