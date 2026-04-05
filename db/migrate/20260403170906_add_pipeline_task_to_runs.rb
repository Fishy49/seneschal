class AddPipelineTaskToRuns < ActiveRecord::Migration[8.1]
  def change
    add_reference :runs, :pipeline_task, null: true, foreign_key: true
  end
end
