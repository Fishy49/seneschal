# Resolves a skill name to a filesystem path across the three location tiers,
# in priority order:
#
#   1. <project.local_path>/.claude/skills/<name>/          source_kind: "project"
#   2. <project.local_path>/.seneschal/skills/<name>/       source_kind: "project_seneschal"
#   3. Rails.root/skills/<name>/                            source_kind: "global"
#
# Returns a Resolved struct with `source_kind` and `absolute_path`, or nil if
# the skill can't be found. A skill is considered to exist at a location when
# a `SKILL.md` file is present at that path.
class SkillLoader
  Resolved = Data.define(:source_kind, :absolute_path)

  SOURCE_KINDS = ["project", "project_seneschal", "global"].freeze

  def self.resolve(name, project: nil)
    new(name, project: project).resolve
  end

  def self.global_root
    Rails.root.join("skills").to_s
  end

  def initialize(name, project: nil)
    @name = name.to_s
    @project = project
  end

  def resolve
    candidates.each do |source_kind, abs|
      return Resolved.new(source_kind: source_kind, absolute_path: abs) if skill_md_present?(abs)
    end
    nil
  end

  # Returns every candidate path for the skill name in priority order,
  # whether or not the skill exists there. Useful for UI affordances like
  # "create this skill at..." and for diagnostic error messages.
  def candidates
    list = []
    if @project&.local_path.present?
      list << ["project",            File.join(@project.local_path, ".claude", "skills", @name)]
      list << ["project_seneschal",  File.join(@project.local_path, ".seneschal", "skills", @name)]
    end
    list << ["global", File.join(self.class.global_root, @name)]
    list
  end

  private

  def skill_md_present?(dir)
    File.file?(File.join(dir, "SKILL.md"))
  end
end
