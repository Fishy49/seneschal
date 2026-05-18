# Persist the worktree branch name on Run so it's stable across the
# allocate → execute → cleanup lifecycle even if the underlying inputs
# that derived it change (task renamed, run resumed after a long gap).
#
# Pre-this-migration, WorktreeManager.branch_for(run) was a pure
# function of run.id — deterministic but not descriptive. Going forward
# the function appends a slug of the task title so GitHub's branch
# listing shows what each branch is about. Caching the result on the
# row protects against the slug shifting under a mid-flight run.
class AddBranchNameToRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :runs, :branch_name, :string
  end
end
