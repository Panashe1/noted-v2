# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.2].define(version: 2026_06_05_051946) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "albums", force: :cascade do |t|
    t.string "title", null: false
    t.string "artist", null: false
    t.integer "release_year"
    t.string "genre"
    t.string "cover_image_url"
    t.text "ai_context"
    t.datetime "ai_context_generated_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "itunes_id"
    t.string "apple_music_url"
    t.index ["itunes_id"], name: "index_albums_on_itunes_id", unique: true
    t.index ["title", "artist"], name: "index_albums_on_title_and_artist", unique: true
  end

  create_table "follows", force: :cascade do |t|
    t.bigint "follower_id", null: false
    t.bigint "following_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["follower_id", "following_id"], name: "index_follows_on_follower_id_and_following_id", unique: true
    t.index ["follower_id"], name: "index_follows_on_follower_id"
    t.index ["following_id"], name: "index_follows_on_following_id"
  end

  create_table "listen_logs", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "album_id", null: false
    t.integer "rating", null: false
    t.text "review"
    t.date "listened_on", null: false
    t.boolean "is_relisten", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["album_id"], name: "index_listen_logs_on_album_id"
    t.index ["user_id", "album_id"], name: "index_listen_logs_on_user_id_and_album_id", unique: true
    t.index ["user_id"], name: "index_listen_logs_on_user_id"
  end

  create_table "track_logs", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "track_id", null: false
    t.date "listened_on", null: false
    t.integer "rating"
    t.text "review"
    t.boolean "is_relisten", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["track_id"], name: "index_track_logs_on_track_id"
    t.index ["user_id", "track_id"], name: "index_track_logs_on_user_id_and_track_id", unique: true
    t.index ["user_id"], name: "index_track_logs_on_user_id"
  end

  create_table "tracks", force: :cascade do |t|
    t.bigint "album_id", null: false
    t.string "title"
    t.integer "position"
    t.integer "duration_ms"
    t.string "itunes_track_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "genre"
    t.index ["album_id"], name: "index_tracks_on_album_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "username", default: "", null: false
    t.string "bio"
    t.string "favourite_genre"
    t.text "ai_taste_profile"
    t.datetime "taste_profile_generated_at"
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "name"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["username"], name: "index_users_on_username", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "follows", "users", column: "follower_id"
  add_foreign_key "follows", "users", column: "following_id"
  add_foreign_key "listen_logs", "albums"
  add_foreign_key "listen_logs", "users"
  add_foreign_key "track_logs", "tracks"
  add_foreign_key "track_logs", "users"
  add_foreign_key "tracks", "albums"
end
