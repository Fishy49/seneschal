class CodeMap < ApplicationRecord
  STATUSES = ["pending", "generating", "ready", "error"].freeze

  belongs_to :project

  validates :status, presence: true, inclusion: { in: STATUSES }

  def ready? = status == "ready"
  def generating? = status == "generating"

  def stale?(threshold: 24.hours)
    generated_at.nil? || generated_at < threshold.ago
  end

  def search(query)
    return [] if query.blank? || !ready?

    sanitized = query.gsub(%r{[^\w\s/.]}, "").strip
    return [] if sanitized.blank?

    fts_query = sanitized.split.map { |t| "#{t}*" }.join(" ")

    sql = <<~SQL.squish
      SELECT path, snippet(code_map_search, 1, '**', '**', '...', 32) as snippet,
             module_name, rank
      FROM code_map_search
      WHERE code_map_search MATCH ? AND code_map_id = ?
      ORDER BY rank LIMIT 50
    SQL
    ActiveRecord::Base.connection.execute(
      ActiveRecord::Base.sanitize_sql_array([sql, fts_query, id])
    ).to_a
  end

  def populate_search_index!
    conn = ActiveRecord::Base.connection
    conn.execute(
      ActiveRecord::Base.sanitize_sql_array(
        ["DELETE FROM code_map_search WHERE code_map_id = ?", id]
      )
    )

    insert_sql = "INSERT INTO code_map_search (path, summary, module_name, language, code_map_id) VALUES (?, ?, ?, ?, ?)"
    file_index.each do |path, info|
      conn.execute(
        ActiveRecord::Base.sanitize_sql_array(
          [insert_sql, path.to_s, info["summary"].to_s, info["module"].to_s, info["language"].to_s, id]
        )
      )
    end
  end
end
