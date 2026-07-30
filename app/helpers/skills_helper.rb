module SkillsHelper
  # Which of the four resolution tiers this skill came from. The order is
  # project .claude > project .seneschal > shared folders > skill repos.
  def skill_source_label(skill)
    case skill.source_kind
    when "project" then "#{skill.project&.name} repository (.claude/skills)"
    when "project_seneschal" then "#{skill.project&.name} repository (.seneschal/skills)"
    when "global" then "Shared skill folder"
    when "skill_repo" then "Skill repo: #{skill.skill_repo&.name}"
    else skill.source_kind.to_s
    end
  end
end
