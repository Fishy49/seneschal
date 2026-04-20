class CreateAssistantMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :assistant_messages do |t|
      t.integer :assistant_conversation_id, null: false
      t.string :role
      t.text :content
      t.json :choices, default: []
      t.json :events, default: []
      t.string :turbo_token

      t.timestamps
    end

    add_index :assistant_messages, [:assistant_conversation_id, :created_at]
    add_foreign_key :assistant_messages, :assistant_conversations, on_delete: :cascade
  end
end
