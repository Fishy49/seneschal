class CreateEvents < ActiveRecord::Migration[8.1]
  # Append-only activity feed. No updated_at: an event is a fact about a
  # moment and is never edited.
  def change
    create_table :events do |t|
      t.references :user, null: true, foreign_key: { on_delete: :nullify }
      t.references :subject, polymorphic: true, null: false
      t.string :action, null: false
      t.json :metadata, null: false, default: {}

      t.datetime :created_at, null: false
    end

    add_index :events, :created_at
  end
end
