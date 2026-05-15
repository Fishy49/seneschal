# Resolves a skill name to a filesystem path across the four location tiers,
# in priority order:
#
#   1. <project.local_path>/.claude/skills/<name>/          source_kind: "project"
#   2. <project.local_path>/.seneschal/skills/<name>/       source_kind: "project_seneschal"
#   3. each path in SkillLoader.global_roots                source_kind: "global"
#   4. each enabled SkillRepo, in priority order            source_kind: "skill_repo"
#
# Returns a Resolved struct with `source_kind` and `absolute_path`, or nil if
# the skill can't be found. A skill is considered to exist at a location when
# a `SKILL.md` file is present at that path.
class SkillLoader
  Resolved = Data.define(:source_kind, :absolute_path)

  SOURCE_KINDS = ["project", "project_seneschal", "global", "skill_repo"].freeze
  DEFAULT_GLOBAL_ROOT = Rails.root.join("skills").to_s.freeze

  def self.resolve(name, project: nil)
    new(name, project: project).resolve
  end

  # Ordered list of global skill roots — operator-managed filesystem paths
  # walked in priority order. Setting["skills_global_roots"] accepts comma- or
  # newline-separated entries. Falls back to the singular `skills_global_root`
  # Setting (legacy from C2), and finally to <rails_root>/skills.
  def self.global_roots
    raw = Setting["skills_global_roots"].presence
    return parse_roots(raw) if raw

    legacy = Setting["skills_global_root"].presence
    return [legacy] if legacy

    [DEFAULT_GLOBAL_ROOT]
  end

  # Where the SkillExporter writes new shared skills. The first entry in
  # global_roots — operators put their "primary" skill location first.
  def self.global_root
    global_roots.first
  end

  def self.parse_roots(raw)
    raw.split(/[\n,]/).map(&:strip).reject(&:empty?)
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

  # Every candidate path for the skill name in priority order, whether or
  # not the skill exists there. Useful for "create this skill at..." UI and
  # diagnostic error messages.
  def candidates
    list = []
    if @project&.local_path.present?
      list << ["project",            File.join(@project.local_path, ".claude", "skills", @name)]
      list << ["project_seneschal",  File.join(@project.local_path, ".seneschal", "skills", @name)]
    end
    self.class.global_roots.each do |root|
      list << ["global", File.join(root, @name)]
    end
    skill_repo_candidates.each { |entry| list << entry }
    list
  end

  private

  def skill_md_present?(dir)
    File.file?(File.join(dir, "SKILL.md"))
  end

  def skill_repo_candidates
    return [] unless defined?(SkillRepo)

    SkillRepo.active_by_priority.map do |repo|
      ["skill_repo", File.join(repo.local_path, @name)]
    end
  end
end
