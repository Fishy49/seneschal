class AddArchivedAtToPipelineTasks < ActiveRecord::Migration[8.1]
  def change
    add_column :pipeline_tasks, :archived_at, :datetime
  end
end
