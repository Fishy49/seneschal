class UpgradeOpus46To47 < ActiveRecord::Migration[8.1]
  def up
    [:steps, :step_templates].each do |table|
      execute <<~SQL.squish
        UPDATE #{table}
        SET config = json_set(config, '$.model', 'claude-opus-4-7')
        WHERE json_extract(config, '$.model') = 'claude-opus-4-6'
      SQL
    end
  end

  def down
    [:steps, :step_templates].each do |table|
      execute <<~SQL.squish
        UPDATE #{table}
        SET config = json_set(config, '$.model', 'claude-opus-4-6')
        WHERE json_extract(config, '$.model') = 'claude-opus-4-7'
      SQL
    end
  end
end
