class AddContextFilesToPipelineTasks < ActiveRecord::Migration[8.1]
  def change
    add_column :pipeline_tasks, :context_files, :json, default: []
  end
end
