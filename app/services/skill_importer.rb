# Scans a project's `.claude/skills/<name>/SKILL.md` files and creates the
# matching Skill rows pointing at them. Filesystem-backed only — the rows
# store `source_kind: "project"` + `relative_path` and resolve their body
# from disk on access. We don't write into the legacy `body` column; the
# row is a pointer, not a copy.
class SkillImporter
  attr_reader :imported, :skipped

  def initialize(project, target: nil)
    @project = project
    @target = target || project
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

    existing = if @target.is_a?(ProjectGroup)
                 Skill.find_by(project_group_id: @target.id, name: name)
               else
                 Skill.find_by(project_id: @target.id, name: name)
               end

    if existing
      @skipped << name
      return
    end

    attrs = {
      name: name,
      source_kind: "project",
      relative_path: dir_name
    }
    attrs[@target.is_a?(ProjectGroup) ? :project_group : :project] = @target

    skill = Skill.create!(attrs)
    skill.refresh_cached_metadata!
    @imported << name
  end
end
