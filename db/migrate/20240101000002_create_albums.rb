class CreateAlbums < ActiveRecord::Migration[7.2]
  def change
    create_table :albums do |t|
      t.string   :title,       null: false
      t.string   :artist,      null: false
      t.integer  :release_year
      t.string   :genre
      t.string   :cover_image_url
      t.text     :ai_context
      t.datetime :ai_context_generated_at

      t.timestamps
    end

    add_index :albums, [:title, :artist], unique: true
  end
end
