class AddRejectionContextToRunSteps < ActiveRecord::Migration[8.1]
  def change
    add_column :run_steps, :rejection_context, :text
  end
end
