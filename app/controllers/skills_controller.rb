class SkillsController < ApplicationController
  before_action :set_skill, only: [:show, :edit, :update, :destroy]

  def index
    @skills = Skill.includes(:project, :project_group).order(:name)
    @project_groups = ProjectGroup.ordered
    return if params[:group_id].blank?

    @skills = if params[:group_id] == "none"
                @skills.where(project_group_id: nil)
              else
                @skills.where(project_group_id: params[:group_id])
              end
  end

  def show; end

  def new
    @skill = Skill.new
  end

  def edit; end

  def create
    @skill = Skill.new(skill_params)
    if @skill.save
      redirect_to @skill, notice: "Skill created."
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    if @skill.update(skill_params)
      redirect_to @skill, notice: "Skill updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @skill.destroy
    redirect_to skills_path, notice: "Skill deleted."
  end

  private

  def set_skill
    @skill = Skill.find(params.expect(:id))
  end

  def skill_params
    attrs = params.expect(
      skill: [:name, :description, :body, :scope, :default_json_schema_id, :default_output_variable]
    )

    # Blank schema_id from the form arrives as "" (empty string). Normalize
    # to nil so the FK doesn't try to look up id=0 and AR clears it cleanly.
    attrs[:default_json_schema_id] = attrs[:default_json_schema_id].presence

    return attrs unless attrs.key?(:scope)

    scope = attrs.delete(:scope)
    case scope
    when /\Agroup:(\d+)\z/
      attrs[:project_group_id] = ::Regexp.last_match(1).to_i
      attrs[:project_id] = nil
    when /\Aproject:(\d+)\z/
      attrs[:project_id] = ::Regexp.last_match(1).to_i
      attrs[:project_group_id] = nil
    else
      attrs[:project_id] = nil
      attrs[:project_group_id] = nil
    end
    attrs
  end
end
