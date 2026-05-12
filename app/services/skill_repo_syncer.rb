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
    _, fetch_err, fetch_status = Open3.capture3(
      "git", "-C", @repo.local_path, "fetch", "--prune", "origin"
    )
    raise "git fetch failed: #{fetch_err.strip}" unless fetch_status.success?

    _, reset_err, reset_status = Open3.capture3(
      "git", "-C", @repo.local_path, "reset", "--hard", "origin/#{@repo.branch}"
    )
    raise "git reset failed: #{reset_err.strip}" unless reset_status.success?
  end

  def upsert_skills
    Dir.glob(File.join(@repo.local_path, "*", "SKILL.md")).map do |path|
      slug = File.basename(File.dirname(path))
      parsed = SkillMdParser.parse(File.read(path))
      name = parsed.frontmatter["name"].presence || slug

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
      name
    end
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
      acc[name] = File.read(notes_path).strip
    end
  end

  def parse_name(skill_md_path)
    SkillMdParser.parse(File.read(skill_md_path)).frontmatter["name"].presence
  rescue StandardError
    nil
  end
end
