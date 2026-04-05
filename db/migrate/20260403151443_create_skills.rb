class CreateSkills < ActiveRecord::Migration[8.1]
  def change
    create_table :skills do |t|
      t.string :name, null: false
      t.text :description
      t.text :body, null: false
      t.references :project, null: true, foreign_key: true

      t.timestamps
    end
  end
end
