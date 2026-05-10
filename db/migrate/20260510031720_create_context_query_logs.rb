class CreateContextQueryLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :context_query_logs do |t|
      t.references :run_step, null: false, foreign_key: { on_delete: :cascade }
      t.string :variable, null: false
      t.text :expression, null: false
      t.integer :returned_bytes, null: false, default: 0
      t.string :error

      t.timestamps
    end
  end
end
