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
    content = File.read(path)
    frontmatter, body = parse_frontmatter(content)

    name = frontmatter["name"] || File.basename(File.dirname(path))
    description = frontmatter["description"]

    existing = @project.skills.find_by(name: name)
    if existing
      @skipped << name
      return
    end

    @project.skills.create!(
      name: name,
      description: description,
      body: body.strip
    )
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
