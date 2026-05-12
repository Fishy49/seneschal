class AddFilesystemFieldsToSkills < ActiveRecord::Migration[8.1]
  # Adds the columns Skills need to live on disk as agentskills.io SKILL.md
  # folders. body:text stays nullable for now — the C2 export rake task will
  # populate the new columns from the existing bodies, and a later migration
  # in PR C3 will drop body once everyone's migrated.
  def change
    add_column :skills, :source_kind, :string
    add_column :skills, :relative_path, :string
    add_column :skills, :content_hash, :string
    add_column :skills, :cached_metadata, :json, default: {}, null: false

    change_column_null :skills, :body, true

    add_index :skills, [:source_kind, :relative_path]
  end
end
