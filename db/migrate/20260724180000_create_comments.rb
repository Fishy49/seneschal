class CreateComments < ActiveRecord::Migration[8.1]
  def change
    create_table :comments do |t|
      t.references :commentable, polymorphic: true, null: false
      t.references :user, null: false, foreign_key: true
      t.text :body, null: false
      # A DOM id from the Replay view, so a comment can point at one
      # trajectory entry rather than the whole run.
      t.string :anchor

      t.timestamps
    end
  end
end
