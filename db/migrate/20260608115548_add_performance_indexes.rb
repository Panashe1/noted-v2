class AddPerformanceIndexes < ActiveRecord::Migration[7.2]
  def change
    # External lookup key, hit on every iTunes import / search dedup
    # (find_by, find_or_create_by, where(itunes_track_id: […])). Unique also gives a
    # DB-level guarantee against duplicate tracks — the app logic alone could race.
    add_index :tracks, :itunes_track_id, unique: true

    # Genre filter on the Albums page: where(genre: …) and the DISTINCT genre pills.
    add_index :albums, :genre

    # Profile log lists: where(user_id: X).order(listened_on: :desc) — a composite
    # index lets Postgres filter AND return rows already sorted (the existing user_id
    # index only covers the filter, leaving an in-memory sort).
    add_index :listen_logs, [:user_id, :listened_on]
    add_index :track_logs,  [:user_id, :listened_on]
  end
end
