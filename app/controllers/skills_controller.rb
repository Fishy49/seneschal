class SkillsController < ApplicationController
  before_action :set_skill, only: [:show, :edit, :update, :destroy]

  def index
    @skills = Skill.includes(:project, :project_group).order(:name)
    @project_groups = ProjectGroup.ordered
    if params[:group_id].present?
      if params[:group_id] == "none"
        @skills = @skills.where(project_group_id: nil)
      else
        @skills = @skills.where(project_group_id: params[:group_id])
      end
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
    @skill = Skill.find(params[:id])
  end

  def skill_params
    attrs = params.expect(skill: [:name, :description, :body, :scope])
    scope = attrs.delete(:scope)
    if scope =~ /\Agroup:(\d+)\z/
      attrs[:project_group_id] = $1.to_i
      attrs[:project_id] = nil
    elsif scope =~ /\Aproject:(\d+)\z/
      attrs[:project_id] = $1.to_i
      attrs[:project_group_id] = nil
    else
      attrs[:project_id] = nil
      attrs[:project_group_id] = nil
    end
    attrs
  end
end
