# Writes an edited SKILL.md back to the file the skill already resolves to.
#
# Two rules make this safe to expose in the browser:
#   1. The destination is ALWAYS the skill's own resolved path. Nothing from
#      the request ever contributes to it.
#   2. A skill synced from a git repository is read-only here, because the
#      next sync would overwrite whatever was typed.
#
# Renaming is refused too: the name is both the frontmatter `name:` and the
# directory on disk, so a rename is a move, not an edit.
class SkillMdWriter
  Result = Data.define(:ok, :error)

  def self.call(skill:, content:) = new(skill, content).call

  def initialize(skill, content)
    @skill = skill
    @content = content.to_s
  end

  def call
    return failure("This skill is synced from #{@skill.skill_repo&.name}. Edit it in that repository.") unless editable?

    path = @skill.skill_md_path
    return failure("This skill has no file on disk yet.") if path.blank? || !File.exist?(path)

    parsed = SkillMdParser.parse(@content)
    new_name = parsed.frontmatter["name"].to_s
    if new_name.present? && new_name != @skill.name
      return failure("Renaming a skill also moves its folder, so it cannot be done here. " \
                     "Keep `name: #{@skill.name}` and rename it on disk instead.")
    end

    File.write(path, @content)
    @skill.refresh_cached_metadata!
    Result.new(ok: true, error: nil)
  end

  private

  def editable? = @skill.source_kind != "skill_repo"

  def failure(message) = Result.new(ok: false, error: message)
end
