require "open3"
require "fileutils"

# Synchronizes a SkillRepo's git checkout and reconciles Skill records:
#
#   - clone or fetch+reset --hard to the configured branch
#   - upsert a Skill row for every */SKILL.md in the repo (source_kind: "skill_repo")
#   - mark Skill rows whose folders disappeared as archived (preserves Step
#     foreign keys; operators see the broken link in the UI rather than
#     silently losing workflow steps)
#   - capture per-skill .install-notes content into SkillRepo#install_notes
#     so the UI can surface setup steps (env vars, MCP servers, deps)
#
# Returns a Result struct (status: :ok | :error, plus per-skill counts).
class SkillRepoSyncer
  Result = Data.define(:status, :imported, :archived, :error)

  # Cap per-skill .install-notes captures so an oversized file in some
  # upstream repo doesn't bloat the install_notes JSON column or the
  # rendered show page.
  MAX_INSTALL_NOTES_BYTES = 10_000

  def initialize(skill_repo)
    @repo = skill_repo
  end

  def call
    ensure_clone_or_pull
    seen = upsert_skills
    archived = archive_missing(seen)

    @repo.update!(
      last_synced_at: Time.current,
      last_sync_error: nil,
      install_notes: collect_install_notes
    )
    Result.new(status: :ok, imported: seen, archived: archived, error: nil)
  rescue StandardError => e
    @repo.update!(last_sync_error: "#{e.class}: #{e.message}")
    Result.new(status: :error, imported: [], archived: [], error: e.message)
  end

  private

  def ensure_clone_or_pull
    @repo.cloned? ? pull : clone
  end

  def clone
    FileUtils.mkdir_p(File.dirname(@repo.local_path))
    _, stderr, status = Open3.capture3(
      "git", "clone", "--branch", @repo.branch, @repo.repo_url, @repo.local_path
    )
    raise "git clone failed: #{stderr.strip}" unless status.success?
  end

  def pull
    # Fetch only the configured branch (passed as a separate argv element so
    # nothing user-supplied is interpolated into a shell-style command arg),
    # then reset to FETCH_HEAD which is a fixed string and known-fresh.
    _, fetch_err, fetch_status = Open3.capture3(
      "git", "-C", @repo.local_path, "fetch", "--prune", "origin", @repo.branch
    )
    raise "git fetch failed: #{fetch_err.strip}" unless fetch_status.success?

    _, reset_err, reset_status = Open3.capture3(
      "git", "-C", @repo.local_path, "reset", "--hard", "FETCH_HEAD"
    )
    raise "git reset failed: #{reset_err.strip}" unless reset_status.success?
  end

  def upsert_skills
    Dir.glob(File.join(@repo.local_path, "*", "SKILL.md")).map do |path|
      slug = File.basename(File.dirname(path))
      parsed = SkillMdParser.parse(File.read(path))
      name = parsed.frontmatter["name"].presence || slug

      warn_on_invalid_frontmatter(slug, parsed.frontmatter)

      skill = Skill.find_or_initialize_by(skill_repo_id: @repo.id, name: name)
      skill.assign_attributes(
        description: parsed.frontmatter["description"],
        source_kind: "skill_repo",
        relative_path: slug,
        cached_metadata: parsed.frontmatter,
        archived_at: nil
      )
      skill.save!
      skill.refresh_cached_metadata!
      auto_import_reference_schemas(skill)
      name
    end
  end

  # Scan a freshly-synced skill's `references/` directory for JSON Schema
  # files (per JsonSchemaSniffer) and import each as a top-level JsonSchema
  # row via the shared SchemaImporter service. Auto-links the skill's
  # `default_json_schema_id` ONLY when there's exactly one schema-y
  # reference AND the skill currently has no default — never clobbers an
  # explicit pick. Multi-schema skills import every row but leave the
  # default for the operator to wire up via the show page.
  def auto_import_reference_schemas(skill)
    schema_refs = skill.references_files.select { |f| f[:looks_like_schema] }
    return if schema_refs.empty?

    auto_link = schema_refs.size == 1
    schema_refs.each do |ref|
      result = SchemaImporter.call(skill: skill, reference: ref[:name],
                                   set_default: auto_link ? :if_blank : :never)
      log_schema_import(skill, ref[:name], result, linked: auto_link)
    end
  end

  def log_schema_import(skill, filename, result, linked:)
    label = "#{@repo.name}/#{skill.name}/references/#{filename}"
    case result.status
    when :imported
      Rails.logger.info(
        "SkillRepoSyncer: imported schema #{label} → JsonSchema \"#{result.schema.name}\"" \
        "#{" (linked as default)" if linked}"
      )
    else
      Rails.logger.warn("SkillRepoSyncer: skipped schema #{label} (#{result.status}): #{result.reason}")
    end
  end

  # Run the SKILL.md frontmatter through the JSON Schema validator and log
  # any failures. The syncer is intentionally permissive — it falls back to
  # the directory name for missing `name` and a nil description, so the
  # import still happens — but operators want visibility when an upstream
  # skill ships broken metadata.
  def warn_on_invalid_frontmatter(slug, frontmatter)
    validation = SkillMdValidator.validate(frontmatter)
    return if validation[:valid]

    Rails.logger.warn(
      "SkillRepoSyncer: invalid SKILL.md frontmatter in #{@repo.name}/#{slug}: " \
      "#{validation[:errors].join("; ")}"
    )
  end

  def archive_missing(seen_names)
    stale = Skill.where(skill_repo_id: @repo.id).where.not(name: seen_names).active
    names = stale.pluck(:name)
    stale.update_all(archived_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    names
  end

  def collect_install_notes
    Dir.glob(File.join(@repo.local_path, "*", ".install-notes")).each_with_object({}) do |notes_path, acc|
      dir = File.dirname(notes_path)
      skill_md = File.join(dir, "SKILL.md")
      next unless File.exist?(skill_md)

      name = parse_name(skill_md) || File.basename(dir)
      acc[name] = read_install_notes(notes_path)
    end
  end

  def read_install_notes(path)
    raw = File.read(path)
    if raw.bytesize > MAX_INSTALL_NOTES_BYTES
      "#{raw.byteslice(0, MAX_INSTALL_NOTES_BYTES).strip}\n\n…(truncated; full file in repo)"
    else
      raw.strip
    end
  end

  def parse_name(skill_md_path)
    SkillMdParser.parse(File.read(skill_md_path)).frontmatter["name"].presence
  rescue StandardError
    nil
  end
end
