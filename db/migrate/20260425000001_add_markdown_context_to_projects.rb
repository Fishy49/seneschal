class AddMarkdownContextToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :markdown_context, :text
  end
end
