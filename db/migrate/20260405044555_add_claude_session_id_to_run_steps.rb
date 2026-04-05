class AddClaudeSessionIdToRunSteps < ActiveRecord::Migration[8.1]
  def change
    add_column :run_steps, :claude_session_id, :string
  end
end
