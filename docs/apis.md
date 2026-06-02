# APIs & External Services

This document covers the two external APIs Noted integrates with — the Apple iTunes Search API and the Anthropic Claude API — including request/response shapes, usage patterns, error codes, and failure modes.

---

## iTunes Search API

**Base URLs:**
- Search endpoint: `https://itunes.apple.com/search`
- Lookup endpoint: `https://itunes.apple.com/lookup`

**Authentication:** None required. The iTunes Search API is free and requires no API key.

**HTTP client:** HTTParty with a 5-second timeout (`MusicSearchService::TIMEOUT = 5`).

**Service class:** `app/services/music_search_service.rb`

---

### `MusicSearchService#search_albums(query)`

Used on the Log Album modal (Step 1 search).

#### Request

```
GET https://itunes.apple.com/search
  ?term=<query>
  &entity=album
  &limit=8
  &media=music
```

| Param | Value | Notes |
|---|---|---|
| `term` | User's search string | URL-encoded automatically by HTTParty |
| `entity` | `album` | Returns `collection` type results |
| `limit` | `8` | Max 8 results; kept small for modal display |
| `media` | `music` | Scopes to music catalogue only |

#### Response shape

```json
{
  "resultCount": 2,
  "results": [
    {
      "wrapperType": "collection",
      "collectionId": 1474690620,
      "collectionName": "OK Computer",
      "artistName": "Radiohead",
      "releaseDate": "1997-05-21T07:00:00Z",
      "primaryGenreName": "Alternative",
      "artworkUrl100": "https://is1-ssl.mzstatic.com/image/thumb/.../100x100bb.jpg",
      "collectionViewUrl": "https://music.apple.com/us/album/...",
      "trackCount": 12
    }
  ]
}
```

#### Field mapping (`parse_album_result`)

| iTunes field | Mapped to | Notes |
|---|---|---|
| `collectionId` | `:itunes_id` | Converted to string |
| `collectionName` | `:title` | |
| `artistName` | `:artist` | |
| `releaseDate` | `:release_year` | Parsed as `Date`, `.year` extracted; `nil` on parse error |
| `primaryGenreName` | `:genre` | |
| `artworkUrl100` | `:cover_url` | `100x100bb` replaced with `600x600bb` for high-res |
| `collectionViewUrl` | `:apple_music_url` | |
| `trackCount` | `:track_count` | Informational; not stored in DB |

Results with no `collectionId` are filtered out via `.compact` (the parser returns `nil` for invalid records).

---

### `MusicSearchService#search_tracks(query)`

Used on the Tracks index page to supplement local results with iTunes data.

#### Request

```
GET https://itunes.apple.com/search
  ?term=<query>
  &entity=song
  &limit=20
  &media=music
```

| Param | Value | Notes |
|---|---|---|
| `entity` | `song` | Returns individual tracks (not albums) |
| `limit` | `20` | Up to 20 song results |

#### Response filtering

After parsing, results are filtered to only include entries where:
- `wrapperType == "track"` (excludes collections/albums that sometimes appear)
- `kind == "song"` (excludes music videos, podcasts, etc.)

#### Field mapping (`parse_track_result`)

| iTunes field | Mapped to | Notes |
|---|---|---|
| `trackId` | `:itunes_track_id` | Converted to string |
| `collectionId` | `:itunes_album_id` | Converted to string |
| `trackName` | `:title` | |
| `artistName` | `:artist` | |
| `collectionName` | `:album_title` | |
| `trackNumber` | `:position` | Integer |
| `trackTimeMillis` | `:duration_ms` | Integer; also formatted as `"M:SS"` string in `:duration` |
| `artworkUrl100` | `:cover_url` | `100x100bb` → `60x60bb` (smaller for list display) |
| `releaseDate` | `:release_year` | Parsed as `Date`, `.year` extracted |
| `collectionType` | `:is_single` | `true` if `"Single"`, `false` otherwise |

Results with no `trackId` or no `collectionId` return `nil` from the parser and are removed by `.compact`.

---

### `MusicSearchService#fetch_album_with_tracks(itunes_id)`

Used for:
1. The Log Album modal Step 2 preview (`MusicController#preview`)
2. Importing albums from the Discover page (`AlbumsController#from_itunes`)
3. Importing tracks from the Tracks index (`TracksController#from_itunes`)
4. `TrackImportJob` — background tracklist import after an album is first created

#### Request

```
GET https://itunes.apple.com/lookup
  ?id=<itunes_id>
  &entity=song
  &country=us
```

| Param | Value | Notes |
|---|---|---|
| `id` | iTunes collection ID | The album's `collectionId` |
| `entity` | `song` | Tells iTunes to also return tracks for this album |
| `country` | `us` | Scopes to the US catalogue; required for consistent results |

#### Response shape

The lookup endpoint returns a flat array of results:
- The **first** result with `wrapperType == "collection"` is the album.
- All results with `wrapperType == "track"` are the individual tracks.

```json
{
  "resultCount": 13,
  "results": [
    { "wrapperType": "collection", "collectionId": 1474690620, ... },
    { "wrapperType": "track", "trackId": 111, "trackName": "Airbag", "trackNumber": 1, ... },
    { "wrapperType": "track", "trackId": 222, "trackName": "Paranoid Android", "trackNumber": 2, ... },
    ...
  ]
}
```

Tracks are sorted by `trackNumber` before returning.

#### Return value

```ruby
{
  album: { itunes_id:, title:, artist:, release_year:, genre:, cover_url:, apple_music_url: },
  tracks: [
    { title:, position:, duration_ms:, itunes_track_id: },
    ...
  ]
}
```

Returns `nil` if:
- The HTTP response has a non-2xx status code
- No result with `wrapperType == "collection"` is found
- A `StandardError` is raised (network error, timeout, JSON parse failure)

---

### Error handling

All three `MusicSearchService` methods follow the same error-handling pattern:

```ruby
rescue StandardError => e
  Rails.logger.error("[MusicSearchService#<method>] #{e.message}")
  []   # or nil for fetch_album_with_tracks
end
```

**Philosophy:** External API failures return empty/nil rather than re-raising. The app degrades gracefully:

| Failure | User-facing result |
|---|---|
| `search_albums` returns `[]` | No search results in the modal; "Can't find it? Add manually" link still works |
| `search_tracks` returns `[]` | No iTunes results on the Tracks index; local results still display |
| `fetch_album_with_tracks` returns `nil` | Redirect back with alert ("Couldn't find that album. Try again.") |

---

### Common iTunes error scenarios

| Scenario | Root cause | Service response |
|---|---|---|
| Timeout (> 5 seconds) | iTunes server slow or unreachable | `StandardError` → `[]` / `nil` |
| Non-2xx HTTP response | Rate limiting or server error | `response.success? == false` → `[]` / `nil` |
| Album not in US catalogue | Album only available in other regions | `resultCount: 0` → `[]` / `nil` |
| `collectionId` missing from result | Malformed response | `parse_album_result` returns `nil`; `.compact` filters it |
| `trackId` missing from track result | Malformed response | `parse_track_result` returns `nil`; `.compact` filters it |
| `releaseDate` unparseable | Non-standard date format | `Date.parse` rescue → `release_year: nil` |

---

## Anthropic Claude API

**Base URL:** Managed by the `anthropic` gem  
**Model:** `claude-sonnet-4-20250514` (`ClaudeService::MODEL`)  
**Max tokens:** 1024 per response (`ClaudeService::MAX_TOKENS`)  
**Authentication:** `ANTHROPIC_API_KEY` environment variable

**Service class:** `app/services/claude_service.rb`

---

### `ClaudeService#generate_taste_profile(user)`

Generates a 3–4 sentence listening taste profile for a user.

#### When it's called

`TasteProfileJob#perform(user_id)` — triggered by `ListenLog#after_create` every 5th album log.

#### Input data

Up to 50 most recent album logs, ordered by `listened_on: :desc`. Formatted as:

```
Artist — Album Title (Genre, rated N/10)
```

#### Prompt

```
You are a music critic and cultural analyst. Based on the following listening log,
write a 3–4 sentence taste profile for this listener. Be specific, insightful,
and avoid generic descriptions. Reference actual patterns you notice.

Listening log:
[album list]

Write the profile in second person (e.g. "You gravitate toward...").
Be evocative and precise — this will appear on their public profile.
```

#### Output

A 3–4 sentence plain-text paragraph stored in `users.ai_taste_profile`.

#### Guard condition

```ruby
return nil if logs.empty?
```

The job skips the API call if the user has no listen logs.

---

### `ClaudeService#generate_album_context(album)`

Generates a 2–3 sentence context card for an album.

#### When it's called

`AlbumContextJob#perform(album_id)` — triggered by `Album#after_create`.

#### Guard condition

```ruby
return if album.ai_context.present?
```

The job is idempotent — if the album already has a context card (e.g., the job was re-enqueued after a transient failure), it skips the API call entirely.

#### Prompt

```
You are a music encyclopaedist. Write a concise 2–3 sentence context card for:

Artist: [artist]
Album: [title]
Year: [release_year]
Genre: [genre]

Cover its cultural significance, sonic character, and why it matters.
Be specific — name influences, era, or notable aspects. Avoid clichés.
Do not start with the album name.
```

#### Output

A 2–3 sentence string stored in `albums.ai_context`.

---

### `ClaudeService#assist_review(album:, rating:, user_notes: nil)`

Drafts a short review for a user based on their rating and optional rough notes.

#### When it's called

`ListenLogsController#assist_review` — called via `POST /listen_logs/assist_review`. A JavaScript-driven feature; the draft is returned as JSON and displayed in the UI without a page reload.

#### Prompt

```
A music listener just finished [artist] — [title] and rated it [rating]/10.
[Their rough notes: "..."] OR [They haven't written anything yet.]

Help them write a short, honest review (3–5 sentences). Match the tone to the rating:
high ratings should feel enthusiastic but not gushing; low ratings should be fair, not cruel.
Write in first person as if you are the listener. Be specific to this album.
Return only the review text — no preamble.
```

#### Output

A 3–5 sentence review returned as `{ draft: "…" }` JSON.

---

### `ClaudeService#recommend(user:, query:)`

Returns 5 album recommendations tailored to the user's taste and a natural-language query.

#### When it's called

`RecommendationsController#index` — synchronous, on every Discover page search. Blocks the HTTP response until Claude replies.

#### Input data

Up to 30 of the user's highest-rated album logs, formatted as:

```
Artist — Album Title (N/10)
```

#### Prompt

```
You are a music recommendation engine with great taste.

This listener's top-rated albums:
[top 30 albums by rating]

Their request: "[query]"

Suggest exactly 5 albums. Return ONLY a valid JSON array — no markdown, no explanation, no code block.
Each object must have these exact keys: title, artist, year, description.
"description" should be one compelling sentence explaining why it fits the request.
"year" should be an integer.
Example format:
[{"title":"In Rainbows","artist":"Radiohead","year":2007,"description":"..."}]
```

#### Output

A JSON array of 5 objects. Claude is explicitly told not to wrap the JSON in markdown fences, but the controller strips fences defensively regardless.

#### Post-processing

After Claude returns, `RecommendationsController#enrich_with_itunes` calls `MusicSearchService#search_albums` once per recommendation to obtain a cover URL and `itunes_id`. This adds up to 5 synchronous iTunes calls to the response time.

---

### `ClaudeService#taste_compatibility(user_a, user_b)`

Generates a 2-sentence compatibility description for two users with a score out of 100.

#### When it's called

Not currently wired to any controller route — this method exists in the service but has no UI surface. It is available for future use.

#### Prompt

```
Compare the music taste of two listeners:

Listener A top artists: [artist list with avg ratings]
Listener B top artists: [artist list with avg ratings]

Write 2 sentences about their compatibility — what they share, how they differ.
Give a compatibility score out of 100 at the end in format: "Compatibility: XX/100"
```

---

### `ClaudeService#call_api(prompt)` — private

The single entry point for all API calls:

```ruby
def call_api(prompt)
  response = @client.messages.create(
    model:      MODEL,
    max_tokens: MAX_TOKENS,
    messages:   [{ role: "user", content: prompt }]
  )
  response.content.first.text
rescue Anthropic::Errors::Error => e
  Rails.logger.error("[ClaudeService] API error: #{e.class} — #{e.message}")
  raise e if Rails.env.development?
  nil
end
```

Key behaviours:
- All prompts are sent as a single user message (no system message, no conversation history).
- Errors in **development** are re-raised so they are visible in the Rails server log and browser.
- Errors in **production** are logged and `nil` is returned; callers handle `nil` gracefully (jobs skip the `update!`; the controller shows an error state).

---

### Error handling

#### `Anthropic::Errors::Error` hierarchy

| Error class | Typical cause |
|---|---|
| `Anthropic::Errors::AuthenticationError` | Invalid or missing `ANTHROPIC_API_KEY` |
| `Anthropic::Errors::RateLimitError` | Too many requests (retry after the suggested delay) |
| `Anthropic::Errors::APIStatusError` | 5xx from Anthropic's servers |
| `Anthropic::Errors::APIConnectionError` | Network error reaching the API |
| `Anthropic::Errors::APITimeoutError` | Response took too long |

All of these inherit from `Anthropic::Errors::Error` and are caught by the single `rescue` clause.

#### Failure modes per feature

| Feature | Claude returns `nil` | User-facing result |
|---|---|---|
| Album context card | `AlbumContextJob` skips `update!` | No context card on the album page |
| Taste profile | `TasteProfileJob` skips `update!` | No taste profile shown on profile page |
| Review assistant | `assist_review` returns `nil` draft | JS receives `{ draft: null }` — UI shows an error state |
| Discover recommendations | `recommend` returns `nil` | `parse_recommendations(nil)` returns `[]` — "Claude couldn't respond right now" message shown |

---

### Environment setup

```bash
# Required for all AI features
export ANTHROPIC_API_KEY="sk-ant-..."

# Sidekiq must be running for background AI jobs
bundle exec sidekiq
```

If `ANTHROPIC_API_KEY` is not set, the `Anthropic::Client` initialises but every `call_api` call raises `Anthropic::Errors::AuthenticationError`. In development this bubbles up as an exception; in production it is caught, logged, and returns `nil`.

iTunes integration requires no environment variables.

---

### Rate limits and performance

| API | Rate limits | Typical latency |
|---|---|---|
| iTunes Search | No documented limits; unofficial ~20 req/s | 200–800 ms |
| Anthropic Claude | Tier-dependent; see Anthropic docs | 1–5 seconds per request |

**AI calls are always async** except for the Discover page. The `AlbumContextJob` and `TasteProfileJob` run in Sidekiq workers on the `:ai` queue, so they never block HTTP responses.

The Discover page (`RecommendationsController#index`) makes a synchronous Claude call plus up to 5 synchronous iTunes calls. On a slow connection or under load, this page can take several seconds to return. No streaming is implemented.
