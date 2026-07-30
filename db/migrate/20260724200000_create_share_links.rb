class CreateShareLinks < ActiveRecord::Migration[8.1]
  def change
    create_table :share_links do |t|
      t.references :run, null: false, foreign_key: true
      t.references :created_by, null: true, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :token, null: false
      t.datetime :expires_at, null: false

      t.timestamps
    end

    add_index :share_links, :token, unique: true
  end
end
