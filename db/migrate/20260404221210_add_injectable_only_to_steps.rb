class AddInjectableOnlyToSteps < ActiveRecord::Migration[8.1]
  def change
    add_column :steps, :injectable_only, :boolean, default: false, null: false
  end
end
