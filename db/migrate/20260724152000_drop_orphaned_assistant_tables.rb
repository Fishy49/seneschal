class DropOrphanedAssistantTables < ActiveRecord::Migration[8.1]
  # These two tables reached structure.sql without ever having a migration on
  # main - debris from the unmerged feature/ai-application-assistant branch,
  # which carries its own migrations if that work is ever revived.
  def up
    drop_table :assistant_messages, if_exists: true
    drop_table :assistant_conversations, if_exists: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
