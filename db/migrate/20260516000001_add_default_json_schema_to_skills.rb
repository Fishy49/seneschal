class AddDefaultJsonSchemaToSkills < ActiveRecord::Migration[8.1]
  def change
    add_reference :skills, :default_json_schema,
                  foreign_key: { to_table: :json_schemas, on_delete: :nullify },
                  null: true
    add_column :skills, :default_output_variable, :string, null: true
  end
end
