class CreatePipelineTasks < ActiveRecord::Migration[8.1]
  def change
    create_table :pipeline_tasks do |t|
      t.string :title, null: false
      t.text :body, null: false
      t.string :kind, null: false, default: "feature"
      t.string :status, null: false, default: "draft"
      t.references :project, null: false, foreign_key: true
      t.references :workflow, null: true, foreign_key: true

      t.timestamps
    end
  end
end
