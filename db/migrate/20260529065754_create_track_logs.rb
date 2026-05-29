class CreateTrackLogs < ActiveRecord::Migration[7.2]
  def change
    create_table :track_logs do |t|
      t.references :user, null: false, foreign_key: true
      t.references :track, null: false, foreign_key: true
      t.date :listened_on, null: false
      t.integer :rating
      t.text :review
      t.boolean :is_relisten, default: false, null: false

      t.timestamps
    end

    add_index :track_logs, [:user_id, :track_id], unique: true
  end
end
