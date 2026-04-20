class CreateAssistantConversations < ActiveRecord::Migration[8.1]
  def change
    create_table :assistant_conversations do |t|
      t.integer :user_id, null: false
      t.integer :project_id
      t.string :claude_session_id
      t.string :status, default: "idle"
      t.string :last_page_path
      t.string :title
      t.string :turbo_token

      t.timestamps
    end

    add_index :assistant_conversations, [:user_id, :updated_at]
    add_foreign_key :assistant_conversations, :users, on_delete: :cascade
    add_foreign_key :assistant_conversations, :projects, on_delete: :cascade
  end
end
