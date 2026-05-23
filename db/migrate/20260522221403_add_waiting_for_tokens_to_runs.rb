class AddWaitingForTokensToRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :runs, :waiting_until, :datetime
    add_column :run_steps, :waiting_until, :datetime
  end
end
