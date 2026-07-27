# Workflows carried trigger fields that nothing read: no form set them, no job
# consulted them, and every row was "manual". Real scheduling lives on
# PipelineTask, whose trigger columns are untouched.
class DropWorkflowTriggerColumns < ActiveRecord::Migration[8.1]
  def up
    remove_column :workflows, :trigger_type
    remove_column :workflows, :trigger_config
  end

  def down
    add_column :workflows, :trigger_type, :string, null: false, default: "manual"
    add_column :workflows, :trigger_config, :json
  end
end
