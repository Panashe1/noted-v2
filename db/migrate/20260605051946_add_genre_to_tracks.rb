class AddGenreToTracks < ActiveRecord::Migration[7.2]
  def change
    add_column :tracks, :genre, :string
  end
end
