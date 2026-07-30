# Scans a project's `.claude/skills/<name>/SKILL.md` files and creates the
# matching Skill rows pointing at them. Filesystem-backed only — the rows
# store `source_kind: "project"` + `relative_path` and resolve their body
# from disk on access. We don't write into the legacy `body` column; the
# row is a pointer, not a copy.
class SkillImporter
  attr_reader :imported, :skipped

  def initialize(project)
    @project = project
    @imported = []
    @skipped = []
  end

  # Both conventions are scanned: `.claude/skills` is what other tools write,
  # and `.seneschal/skills` is where SkillScaffolder puts skills created here.
  SKILL_DIRS = {
    "project" => [".claude", "skills"],
    "project_seneschal" => [".seneschal", "skills"]
  }.freeze

  def call
    dirs = SKILL_DIRS.filter_map do |source_kind, segments|
      path = File.join(@project.local_path, *segments)
      [source_kind, path] if File.directory?(path)
    end
    return if dirs.empty?

    dirs.each do |source_kind, skills_dir|
      Dir.glob(File.join(skills_dir, "*", "SKILL.md")).each do |path|
        import_skill(path, source_kind)
      end
    end

    { imported: @imported, skipped: @skipped }
  end

  private

  def import_skill(path, source_kind)
    parsed = SkillMdParser.parse(File.read(path))
    frontmatter = parsed.frontmatter

    dir_name = File.basename(File.dirname(path))
    name = frontmatter["name"] || dir_name

    if Skill.find_by(project_id: @project.id, name: name)
      @skipped << name
      return
    end

    skill = Skill.create!(
      name: name,
      project: @project,
      source_kind: source_kind,
      relative_path: dir_name
    )
    skill.refresh_cached_metadata!
    @imported << name
  end
end
