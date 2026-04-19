class AddTriggerFieldsToPipelineTasks < ActiveRecord::Migration[8.1]
  def change
    add_column :pipeline_tasks, :trigger_type, :string, default: "manual", null: false
    add_column :pipeline_tasks, :trigger_config, :json, default: {}, null: false
    add_index :pipeline_tasks, :trigger_type
  end
end
