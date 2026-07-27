class AddDescriptionToStepTemplates < ActiveRecord::Migration[8.1]
  def change
    add_column :step_templates, :description, :text
  end
end
