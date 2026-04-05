class AddSkillAndBodyToSteps < ActiveRecord::Migration[8.1]
  def change
    add_reference :steps, :skill, null: true, foreign_key: true
    add_column :steps, :body, :text
  end
end
