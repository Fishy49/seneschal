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
    content = File.read(path)
    frontmatter, body = parse_frontmatter(content)

    name = frontmatter["name"] || File.basename(File.dirname(path))
    description = frontmatter["description"]

    existing = if @target.is_a?(ProjectGroup)
      Skill.find_by(project_group_id: @target.id, name: name)
    else
      Skill.find_by(project_id: @target.id, name: name)
    end

    if existing
      @skipped << name
      return
    end

    if @target.is_a?(ProjectGroup)
      Skill.create!(name: name, description: description, body: body.strip, project_group: @target)
    else
      Skill.create!(name: name, description: description, body: body.strip, project: @target)
    end
    @imported << name
  end

  def parse_frontmatter(content)
    if content.start_with?("---")
      parts = content.split("---", 3)
      if parts.length >= 3
        frontmatter = YAML.safe_load(parts[1]) || {}
        body = parts[2]
        return [frontmatter, body]
      end
    end

    [{}, content]
  end
end
