class AddProjectGroupIdToProjects < ActiveRecord::Migration[8.1]
  def change
    add_reference :projects, :project_group, null: true, foreign_key: true
  end
end
