# Tests

This document covers how the Noted test suite is organised, the helpers available, what is tested, and what remains uncovered.

---

## Test framework

Noted uses **Rails' built-in test stack**:

| Component | Tool |
|---|---|
| Test framework | Minitest (bundled with Rails) |
| Test runner | `rails test` |
| Fixtures | YAML (`test/fixtures/`) |
| Database | Separate `noted_test` PostgreSQL database |
| Parallelisation | `parallelize(workers: :number_of_processors)` |

No RSpec or FactoryBot are used. Fixtures provide all test data.

---

## File structure

```
test/
├── test_helper.rb                      # Global setup, helpers, compatibility patch
├── fixtures/
│   ├── users.yml
│   ├── albums.yml
│   ├── tracks.yml
│   ├── track_logs.yml
│   ├── listen_logs.yml
│   └── follows.yml
├── models/
│   └── track_log_test.rb
├── controllers/
│   ├── tracks_controller_test.rb
│   └── track_logs_controller_test.rb
└── services/
    └── music_search_service_test.rb
```

---

## `test_helper.rb`

**File:** `test/test_helper.rb`

The global test helper configures the environment and provides shared utilities.

### Minitest 6 / Rails 7.2 compatibility patch

Rails' `LineFiltering` module defines `run(reporter, options={})` with two arguments. Minitest 6 changed its runner to call `run(reporter, reporter, options)` with three arguments, which raised `ArgumentError`. The patch adds a splat-accepting override:

```ruby
if Gem::Version.new(Minitest::VERSION) >= Gem::Version.new("6")
  module Rails
    module LineFiltering
      def run(reporter, *args)
        super
      end
    end
  end
end
```

This is only needed while the installed Rails and Minitest versions have this incompatibility.

### Devise test helpers

```ruby
class ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
end

class ActionController::TestCase
  include Devise::Test::ControllerHelpers
end
```

These inclusions make `sign_in(user)` and `sign_out` available in integration and controller tests respectively. Without them, every test would need to manually POST to the Devise session endpoint.

### `valid_track_log_params(track:, overrides: {})`

A convenience helper for building a minimal valid `track_log` params hash:

```ruby
def valid_track_log_params(track:, overrides: {})
  {
    track_log: {
      track_id:    track.id,
      listened_on: Date.today.iso8601,
      rating:      nil,
      review:      nil,
      is_relisten: false
    }.merge(overrides)
  }
end
```

Usage:

```ruby
post track_logs_path, params: valid_track_log_params(track: @track, overrides: { rating: 8 })
```

### `stub_instance_method(klass, method_name, return_value_or_callable, &block)`

Minitest 6 removed `stub_any_instance`. This helper replaces it for stubbing instance methods:

```ruby
def stub_instance_method(klass, method_name, return_value_or_callable, &block)
  original = klass.instance_method(method_name)
  callable = return_value_or_callable.respond_to?(:call) ?
    return_value_or_callable : ->(*_) { return_value_or_callable }
  klass.define_method(method_name, callable)
  block.call
ensure
  klass.define_method(method_name, original)
end
```

The `ensure` clause restores the original method even if the block raises, preventing test pollution.

**Usage examples:**

```ruby
# Fixed return value
stub_instance_method(MusicSearchService, :search_tracks, []) do
  get tracks_path
end

# Callable — different return value per invocation
stub_instance_method(MusicSearchService, :fetch_album_with_tracks, ->(_id) { nil }) do
  get from_itunes_tracks_path, params: { ... }
end

# Fail loudly if the method is called at all
stub_instance_method(MusicSearchService, :fetch_album_with_tracks,
  ->(_) { flunk "should not call iTunes" }) do
  get from_itunes_tracks_path, params: { ... }
end
```

---

## Fixtures

Fixtures are YAML files that pre-populate the test database before each test. They use symbolic names that become Ruby method-style accessors in tests (e.g., `users(:alice)`).

### `users.yml`

```yaml
alice:
  username: alice
  email: alice@example.com
  encrypted_password: $2a$04$…  # "password123" at MIN_COST

bob:
  username: bob
  email: bob@example.com
  encrypted_password: $2a$04$…  # same password
```

Two users with known credentials. bcrypt hashes are pre-computed at `MIN_COST` to keep fixture loading fast. Re-generate with:

```bash
ruby -e "require 'bcrypt'; puts BCrypt::Password.create('password123', cost: BCrypt::Engine::MIN_COST)"
```

### `albums.yml`

```yaml
ok_computer:
  title: OK Computer
  artist: Radiohead
  release_year: 1997
  genre: Alternative
  itunes_id: "12345"

abbey_road:
  title: Abbey Road
  artist: The Beatles
  release_year: 1969
  genre: Rock
  itunes_id: "67890"
```

### `tracks.yml`

```yaml
paranoid_android:
  album: ok_computer
  title: Paranoid Android
  position: 2
  duration_ms: 383666
  itunes_track_id: "111"

karma_police:
  album: ok_computer
  title: Karma Police
  position: 6
  duration_ms: 263666
  itunes_track_id: "222"

come_together:
  album: abbey_road
  title: Come Together
  position: 1
  duration_ms: 259000
  itunes_track_id: "333"
```

Three tracks across two albums. `paranoid_android` is pre-logged by alice; `karma_police` is the "clean" track used when tests need a track with no existing logs.

### `track_logs.yml`

```yaml
alice_paranoid_android:
  user: alice
  track: paranoid_android
  listened_on: "2024-01-15"
  rating: 9
  review: "Masterpiece."
  is_relisten: false
```

One log. Alice has already logged `paranoid_android`, making it useful for testing duplicate-log rejection and ownership checks.

### `listen_logs.yml`

```
# Empty — no listen_logs needed by these tests, but the table must exist.
```

The `listen_logs` table is present but empty. Tests that need listen logs create them inline.

### `follows.yml`

```
# (empty or minimal — no follow relationships needed by current tests)
```

---

## Model tests

### `TrackLogTest` — `test/models/track_log_test.rb`

Tests the `TrackLog` model in isolation.

#### Setup

```ruby
def setup
  @alice = users(:alice)
  @bob   = users(:bob)
  @track = tracks(:karma_police)  # not yet logged by anyone
end
```

#### Presence validation — `listened_on`

| Test | Assertion |
|---|---|
| Valid with all required attributes (no rating) | `assert log.valid?` |
| Invalid without `listened_on` | `assert_includes errors[:listened_on], "can't be blank"` |

#### Rating validation — 1..10 integer or nil

| Test | Scenario |
|---|---|
| Valid with rating 1 | Lower boundary |
| Valid with rating 10 | Upper boundary |
| Valid with rating nil | Rating is optional |
| Invalid with rating 0 | Below minimum |
| Invalid with rating 11 | Above maximum |
| Invalid with rating 7.5 | Non-integer (validates `only_integer: true`) |

#### Uniqueness — one log per user per track

| Test | Scenario |
|---|---|
| Invalid when user already logged the same track | Alice has a fixture log for `paranoid_android` |
| Valid when a different user logs the same track | Bob can log `paranoid_android` even though Alice already has |

#### Associations

| Test | Assertion |
|---|---|
| Responds to `:user` | `assert_respond_to TrackLog.new, :user` |
| Responds to `:track` | `assert_respond_to TrackLog.new, :track` |
| Invalid without a user | `assert log.errors[:user].any?` |
| Invalid without a track | `assert log.errors[:track].any?` |

#### No taste-profile side effect

```ruby
test "TrackLog has no after_create callback that triggers taste profile regeneration" do
  taste_callbacks = TrackLog._create_callbacks.map(&:filter).map(&:to_s)
  assert_not taste_callbacks.any? { |c| c.include?("taste_profile") }
end
```

This test inspects the model's callback chain directly using Rails' internal `_create_callbacks` API. It verifies the architectural decision that track logs are isolated from the taste system.

---

## Controller tests

### `TracksControllerTest` — `test/controllers/tracks_controller_test.rb`

Integration tests using `ActionDispatch::IntegrationTest`. Signs in alice by default.

#### INDEX

| Test | Verifies |
|---|---|
| Returns 200 with no query | Basic page load works |
| Returns 200 with a short query (< 2 chars) | Short queries don't crash |
| Filters local tracks by title when query ≥ 2 chars | Search logic works |
| Excludes local tracks already in DB from iTunes results | De-duplication logic |

The index tests stub `MusicSearchService#search_tracks` to prevent real HTTP calls:

```ruby
stub_instance_method(MusicSearchService, :search_tracks, []) do
  get tracks_path
end
```

#### SHOW

| Test | Verifies |
|---|---|
| Returns 200 for a valid track | Basic show page loads |
| Returns 404 for an unknown id | `RecordNotFound` → 404 in middleware |

#### FROM_ITUNES — missing params

| Test | Verifies |
|---|---|
| Redirects with alert when `itunes_track_id` is blank | Param validation |
| Redirects with alert when `itunes_album_id` is blank | Param validation |
| Redirects with alert when both params are missing | Both missing |

All redirect to `tracks_path` and the flash alert is verified after `follow_redirect!`.

#### FROM_ITUNES — track already in DB

```ruby
test "from_itunes redirects to track_path without creating duplicates when track exists" do
  assert_no_difference "Track.count" do
    stub_instance_method(MusicSearchService, :fetch_album_with_tracks,
                         ->(_) { flunk "should not call iTunes when track already exists" }) do
      get from_itunes_tracks_path,
          params: { itunes_track_id: @track.itunes_track_id,
                    itunes_album_id: @album.itunes_id }
    end
  end
  assert_redirected_to track_path(@track)
end
```

This test uses `flunk` inside the stub to actively fail if the iTunes service is called — proving the controller takes the early-exit path.

#### FROM_ITUNES — new track

Tests that submitting valid iTunes params for an unknown track creates one `Track` record and redirects to its page. The stub provides a realistic iTunes-shaped response hash.

#### FROM_ITUNES — iTunes lookup fails

Tests that a `nil` return from the service produces a redirect with an alert matching `/Couldn't load.*iTunes/i`. Checks `flash[:alert]` directly rather than parsing the HTML body for more reliable assertion.

---

### `TrackLogsControllerTest` — `test/controllers/track_logs_controller_test.rb`

Integration tests. Alice has a fixture log for `paranoid_android`. Bob has no logs.

#### CREATE

| Test | Verifies |
|---|---|
| Logged-in user creates a log, redirected to track page | Happy path; count increments |
| Unauthenticated request redirected to sign-in | `authenticate_user!` guard |
| Duplicate log returns error redirect, not 500 | Validation error handled gracefully |

The duplicate-log test asserts `assert_response :redirect` (not `5xx`) and checks the flash message matches `/already logged|edit your existing/i` after following the redirect.

#### EDIT

| Test | Verifies |
|---|---|
| User can access edit page for their own log | Own-record access |
| User cannot access edit page for another user's log | Returns 404 (ownership scoping) |

#### UPDATE

| Test | Verifies |
|---|---|
| Valid params save changes and redirect to track page | Fields actually persisted (reload + assert) |
| Invalid params (blank `listened_on`) re-render edit with 422 | `status: :unprocessable_entity` |

The valid-update test uses `.reload` to re-fetch from the database and assert the new values were actually saved:

```ruby
@alices_log.reload
assert_equal 10,   @alices_log.rating
assert_equal true, @alices_log.is_relisten
```

#### DESTROY

| Test | Verifies |
|---|---|
| Destroys the log and redirects to track page | Count decrements; flash shown |
| User cannot destroy someone else's log | 404 (ownership scoping) |

---

## Service tests

### `MusicSearchServiceTest` — `test/services/music_search_service_test.rb`

Unit tests for `MusicSearchService` with all HTTP calls stubbed.

#### Helpers

**`fake_response(success:, body:, code:)`** — Builds a minimal `OpenStruct` that mimics an `HTTParty::Response`:

```ruby
OpenStruct.new(success?: success, body: body.to_json, code: code)
```

**`stub_httparty(return_value_or_callable, &block)`** — Replaces `HTTParty.get` with a fixed value or callable for the duration of the block using `define_singleton_method`:

```ruby
def stub_httparty(return_value_or_callable, &block)
  original = HTTParty.singleton_method(:get)
  callable = ...
  HTTParty.define_singleton_method(:get, callable)
  block.call
ensure
  HTTParty.define_singleton_method(:get, original)
end
```

**`itunes_song_result(overrides = {})`** — Returns a realistic iTunes "song" result hash (Creep by Radiohead, 1993).

**`itunes_album_result(overrides = {})`** — Returns a realistic iTunes "collection" (album) hash.

#### `search_tracks` — blank / empty queries

| Test | Scenario |
|---|---|
| Returns `[]` for blank query | No HTTP call made (stub uses `flunk`) |
| Returns `[]` for nil query | Same |
| Returns `[]` for whitespace-only query | Same |

The `flunk` inside the stub ensures no HTTP call is made for blank queries — the test would fail if `HTTParty.get` were called.

#### `search_tracks` — field parsing

| Test | Field verified |
|---|---|
| `itunes_track_id` parsed from `trackId` | `"123456"` (string, not integer) |
| `itunes_album_id` parsed from `collectionId` | `"789012"` |
| `title`, `artist`, `album_title` parsed correctly | Correct mapping |
| `is_single: false` for album songs | `collectionType == "Album"` |
| `is_single: true` when `collectionType == "Single"` | Correct flag |
| Filters out results where `wrapperType != "track"` | Collections excluded |
| Filters out results where `kind != "song"` | Music videos excluded |
| Returns `[]` when results array is empty | Empty body handled |

#### `search_tracks` — HTTP errors

| Test | Scenario |
|---|---|
| Returns `[]` on HTTP 500 | `success? == false` |
| Returns `[]` when `HTTParty` raises `StandardError` | Connection refused / timeout |

Both error paths return `[]` rather than re-raising, because the view degrades gracefully to an empty iTunes results section.

#### `parse_track_result` — `is_single` flag

| Test | Scenario |
|---|---|
| Marks `is_single: true` when `collectionType == "Single"` | Via public `search_tracks` interface |
| Marks `is_single: false` when `collectionType == "Album"` | Same |
| Returns `nil` (filtered out) when `trackId` is absent | `compact` in service removes nils |

---

## Test coverage gaps

The following areas have no automated tests at the time of writing:

| Area | Notes |
|---|---|
| `AlbumsController` | No tests for `show`, `index`, or `from_itunes` |
| `ListenLogsController` | No tests for `create`, `update`, `destroy`, or `assist_review` |
| `UsersController` | No tests for `show`, `search`, `settings`, or `update_settings` |
| `FollowsController` | No tests for follow/unfollow |
| `RecommendationsController` | No tests for `index` or the JSON parsing / iTunes enrichment |
| `MusicController` | No tests for `search` or `preview` |
| `User` model | No unit tests (validations, avatar upload, `average_rating`) |
| `Album` model | No unit tests (callbacks, `cover_url`, `average_rating`) |
| `Track` model | No unit tests (`default_scope`, `duration_formatted`, `average_rating`) |
| `ListenLog` model | No unit tests (taste-profile callback, rating validation) |
| `Follow` model | No unit tests (`cannot_follow_self`) |
| `ClaudeService` | Not tested (would require live API or complex mocking) |
| `MusicSearchService#search_albums` | Not tested |
| `MusicSearchService#fetch_album_with_tracks` | Not tested |
| Background jobs | `AlbumContextJob`, `TasteProfileJob`, `TrackImportJob` have no tests |
| View/system tests | No Capybara or system tests |

---

## Running the tests

```bash
# Run all tests
rails test

# Run a single file
rails test test/models/track_log_test.rb

# Run a single test by line number
rails test test/controllers/tracks_controller_test.rb:71

# Run with verbose output
rails test -v
```

Ensure the test database is up to date before running:

```bash
rails db:test:prepare
```

Sidekiq is **not** required for the test suite — background jobs that would normally be enqueued are not executed in the test environment (jobs are configured to use the inline adapter or are stubbed where necessary).
