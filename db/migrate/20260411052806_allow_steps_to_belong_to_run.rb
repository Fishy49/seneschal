class AllowStepsToBelongToRun < ActiveRecord::Migration[8.1]
  def change
    change_column_null :steps, :workflow_id, true
    add_reference :steps, :run, foreign_key: true, null: true
  end
end
