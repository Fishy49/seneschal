class AddSkipPermissionsToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :skip_permissions, :boolean, default: false, null: false
  end
end
