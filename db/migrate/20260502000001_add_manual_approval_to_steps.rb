class AddManualApprovalToSteps < ActiveRecord::Migration[8.1]
  def change
    add_column :steps, :manual_approval, :boolean, default: false, null: false
    add_column :step_templates, :manual_approval, :boolean, default: false, null: false
  end
end
