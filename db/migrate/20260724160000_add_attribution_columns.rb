class AddAttributionColumns < ActiveRecord::Migration[8.1]
  # All nullable: cron ticks and branch-watch polls start runs with no human
  # behind them, and every row that predates this migration has no actor.
  # Deleting a user nullifies the reference rather than cascading.
  def change
    add_reference :pipeline_tasks, :created_by, null: true,
                                                foreign_key: { to_table: :users, on_delete: :nullify }
    add_reference :workflows, :created_by, null: true,
                                           foreign_key: { to_table: :users, on_delete: :nullify }
    add_reference :runs, :started_by, null: true,
                                      foreign_key: { to_table: :users, on_delete: :nullify }
    add_reference :runs, :stopped_by, null: true,
                                      foreign_key: { to_table: :users, on_delete: :nullify }
  end
end
