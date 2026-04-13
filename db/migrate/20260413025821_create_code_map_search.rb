class CreateCodeMapSearch < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL # rubocop:disable Rails/SquishedSQLHeredocs
      CREATE VIRTUAL TABLE code_map_search USING fts5(
        path,
        summary,
        module_name,
        language,
        code_map_id UNINDEXED,
        tokenize='porter unicode61'
      );
    SQL
  end

  def down
    execute "DROP TABLE IF EXISTS code_map_search;"
  end
end
