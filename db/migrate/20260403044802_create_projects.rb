class CreateProjects < ActiveRecord::Migration[8.1]
  def change
    create_table :projects do |t|
      t.string :name, null: false
      t.string :repo_url, null: false
      t.string :local_path, null: false
      t.text :description

      t.timestamps
    end
  end
end
