class CreateCodeMaps < ActiveRecord::Migration[8.1]
  def change
    create_table :code_maps do |t|
      t.references :project, null: false, foreign_key: true, index: { unique: true }
      t.json :tree, null: false, default: []
      t.json :modules, null: false, default: []
      t.json :file_index, null: false, default: {}
      t.string :status, null: false, default: "pending"
      t.text :error_message
      t.string :commit_sha
      t.integer :file_count, default: 0
      t.datetime :generated_at
      t.timestamps
    end
  end
end
