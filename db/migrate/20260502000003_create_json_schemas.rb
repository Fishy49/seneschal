class CreateJsonSchemas < ActiveRecord::Migration[8.1]
  def change
    create_table :json_schemas do |t|
      t.string :name, null: false
      t.text :description
      t.text :body, null: false
      t.timestamps
    end

    add_index :json_schemas, :name, unique: true
  end
end
