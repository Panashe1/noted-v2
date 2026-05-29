class CreateListenLogs < ActiveRecord::Migration[7.2]
  def change
    create_table :listen_logs do |t|
      t.references :user,  null: false, foreign_key: true
      t.references :album, null: false, foreign_key: true
      t.integer    :rating,      null: false
      t.text       :review
      t.date       :listened_on, null: false
      t.boolean    :is_relisten, default: false, null: false

      t.timestamps
    end

    add_index :listen_logs, [:user_id, :album_id], unique: true
  end
end
