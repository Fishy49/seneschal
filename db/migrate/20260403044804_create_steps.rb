class CreateSteps < ActiveRecord::Migration[8.1]
  def change
    create_table :steps do |t|
      t.string :name, null: false
      t.integer :position, null: false
      t.string :step_type, null: false
      t.json :config, null: false, default: {}
      t.integer :max_retries, null: false, default: 0
      t.integer :timeout, null: false, default: 600
      t.references :workflow, null: false, foreign_key: true

      t.timestamps
    end
  end
end
