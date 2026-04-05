class CreateRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :runs do |t|
      t.string :status, null: false, default: "pending"
      t.json :context, null: false, default: {}
      t.json :input, null: false, default: {}
      t.datetime :started_at
      t.datetime :finished_at
      t.text :error_message
      t.references :workflow, null: false, foreign_key: true

      t.timestamps
    end
  end
end
