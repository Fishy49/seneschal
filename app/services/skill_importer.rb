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

  def call
    skills_dir = File.join(@project.local_path, ".claude", "skills")
    return unless File.directory?(skills_dir)

    Dir.glob(File.join(skills_dir, "*", "SKILL.md")).each do |path|
      import_skill(path)
    end

    { imported: @imported, skipped: @skipped }
  end

  private

  def import_skill(path)
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
      source_kind: "project",
      relative_path: dir_name
    )
    skill.refresh_cached_metadata!
    @imported << name
  end
end
