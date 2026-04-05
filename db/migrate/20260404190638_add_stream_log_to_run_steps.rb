class AddStreamLogToRunSteps < ActiveRecord::Migration[8.1]
  def change
    add_column :run_steps, :stream_log, :json
  end
end
