class CreateRunSteps < ActiveRecord::Migration[8.1]
  def change
    create_table :run_steps do |t|
      t.string :status, null: false, default: "pending"
      t.integer :attempt, null: false, default: 1
      t.text :output
      t.text :error_output
      t.integer :exit_code
      t.datetime :started_at
      t.datetime :finished_at
      t.float :duration
      t.references :run, null: false, foreign_key: true
      t.references :step, null: false, foreign_key: true

      t.timestamps
    end
  end
end
