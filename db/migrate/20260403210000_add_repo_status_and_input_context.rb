class AddRepoStatusAndInputContext < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :repo_status, :string, null: false, default: "not_cloned"
    add_column :steps, :input_context, :text
  end
end
