class AddWorktreeFieldsToRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :runs, :worktree_path, :string
    add_column :runs, :worktree_retained, :boolean, default: false, null: false
    add_index :runs, :worktree_retained, where: "worktree_retained = 1",
                                         name: "index_runs_on_worktree_retained_true"
  end
end
