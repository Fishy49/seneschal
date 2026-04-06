class CreateStepTemplates < ActiveRecord::Migration[8.1]
  def change
    create_table :step_templates do |t|
      t.string :name, null: false
      t.string :step_type, null: false
      t.text :body
      t.json :config, default: {}, null: false
      t.references :skill, foreign_key: true
      t.integer :max_retries, default: 0, null: false
      t.integer :timeout, default: 600, null: false
      t.text :input_context
      t.boolean :injectable_only, default: false, null: false
      t.timestamps
    end
    add_index :step_templates, :name, unique: true
  end
end
