class AddItunesFieldsToAlbums < ActiveRecord::Migration[7.2]
  def change
    add_column :albums, :itunes_id, :string
    add_column :albums, :apple_music_url, :string
    add_index  :albums, :itunes_id, unique: true
  end
end
