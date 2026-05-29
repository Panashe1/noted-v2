class CreateTracks < ActiveRecord::Migration[7.2]
  def change
    create_table :tracks do |t|
      t.references :album, null: false, foreign_key: true
      t.string :title
      t.integer :position
      t.integer :duration_ms
      t.string :itunes_track_id

      t.timestamps
    end
  end
end
