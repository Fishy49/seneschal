# Drops the `project_group_id` column from `skills`. Group-scoped Skills
# are being retired (no on-disk projection in the agentskills.io model,
# zero real-world usage in this install). ProjectGroup itself stays —
# only its Skills association goes away.
#
# A previous data-task already deleted the one DB-only legacy Skill that
# had a project_group_id set, so this migration is safe to apply with
# zero risk of orphaning rows.
class DropProjectGroupFromSkills < ActiveRecord::Migration[8.1]
  def change
    remove_reference :skills, :project_group, foreign_key: true, null: true
  end
end
