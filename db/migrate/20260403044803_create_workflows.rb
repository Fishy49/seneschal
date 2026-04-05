class CreateWorkflows < ActiveRecord::Migration[8.1]
  def change
    create_table :workflows do |t|
      t.string :name, null: false
      t.text :description
      t.string :trigger_type, null: false, default: "manual"
      t.json :trigger_config
      t.references :project, null: false, foreign_key: true

      t.timestamps
    end
  end
end
