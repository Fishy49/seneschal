class AddPositionAndInputContextToRunSteps < ActiveRecord::Migration[8.1]
  def change
    add_column :run_steps, :position, :integer
    add_column :run_steps, :resolved_input_context, :text
  end
end
