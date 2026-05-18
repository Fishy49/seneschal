# Drops the legacy `body` column from `skills`. Every skill is filesystem-
# backed (agentskills.io) now — `Skill#body` resolves to the parsed body of
# the on-disk SKILL.md, never the DB column. The previous two phases
# (#28, #29) tightened the validators and migrated every code path off the
# column; this migration is the irreversible final step.
#
# Safe to apply unconditionally: zero callers reference `read_attribute(:body)`
# or raw SQL against the column, and the AR-level `body` accessor has been
# overridden to read from disk for a full release.
class DropBodyFromSkills < ActiveRecord::Migration[8.1]
  def up
    remove_column :skills, :body
  end

  def down
    add_column :skills, :body, :text
  end
end
