class CreateProjectGroups < ActiveRecord::Migration[8.1]
  def change
    create_table :project_groups do |t|
      t.string :name, null: false
      t.text :description

      t.timestamps
    end

    add_index :project_groups, :name, unique: true
  end
end
