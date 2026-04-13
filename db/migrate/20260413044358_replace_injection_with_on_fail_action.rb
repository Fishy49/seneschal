class ReplaceInjectionWithOnFailAction < ActiveRecord::Migration[8.1]
  def change
    add_column :run_steps, :parent_run_step_id, :integer
    add_index :run_steps, :parent_run_step_id
    remove_column :steps, :injectable_only, :boolean, default: false, null: false
    remove_column :step_templates, :injectable_only, :boolean, default: false, null: false
  end
end
