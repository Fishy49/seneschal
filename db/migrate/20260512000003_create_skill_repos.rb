class CreateSkillRepos < ActiveRecord::Migration[8.1]
  def change
    create_table :skill_repos do |t|
      t.string :name, null: false
      t.string :repo_url, null: false
      t.string :local_path, null: false
      t.string :branch, null: false, default: "main"
      t.boolean :enabled, null: false, default: true
      t.integer :priority, null: false, default: 100
      t.datetime :last_synced_at
      t.text :last_sync_error
      t.json :install_notes, null: false, default: {}

      t.timestamps
    end

    add_index :skill_repos, :name, unique: true
    add_index :skill_repos, [:enabled, :priority]

    add_reference :skills, :skill_repo, foreign_key: true, null: true
    add_column :skills, :archived_at, :datetime
    add_index :skills, :archived_at
  end
end
