class CreateApprovalEvents < ActiveRecord::Migration[8.1]
  # An append-only record of every approve / reject decision. The job still
  # reads and clears RunStep#rejection_context; these rows are the durable
  # human-readable history that survives that clear.
  def change
    create_table :approval_events do |t|
      t.references :run_step, null: false, foreign_key: true
      t.references :user, null: true, foreign_key: { on_delete: :nullify }
      t.string :action, null: false
      t.text :comment

      t.timestamps
    end
  end
end
