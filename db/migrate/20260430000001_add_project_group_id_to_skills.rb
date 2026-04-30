class AddProjectGroupIdToSkills < ActiveRecord::Migration[8.1]
  def change
    add_reference :skills, :project_group, null: true, foreign_key: true
  end
end
