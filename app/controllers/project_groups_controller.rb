class ProjectGroupsController < ApplicationController
  before_action :set_group, only: [:show, :edit, :update, :destroy]

  def index
    @groups = ProjectGroup.ordered.includes(:projects, :skills)
  end

  def show
    @projects = @group.projects.order(:name)
    @skills = @group.skills.order(:name)
  end

  def new
    @group = ProjectGroup.new
  end

  def edit; end

  def create
    @group = ProjectGroup.new(group_params)
    if @group.save
      respond_to do |format|
        format.html { redirect_to project_groups_path, notice: "Group created." }
        format.json { render json: { id: @group.id, name: @group.name }, status: :created }
      end
    else
      respond_to do |format|
        format.html { render :new, status: :unprocessable_content }
        format.json { render json: { errors: @group.errors.full_messages }, status: :unprocessable_content }
      end
    end
  end

  def update
    if @group.update(group_params)
      redirect_to project_groups_path, notice: "Group updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @group.destroy
    redirect_to project_groups_path, notice: "Group deleted."
  end

  private

  def set_group
    @group = ProjectGroup.find(params[:id])
  end

  def group_params
    params.expect(project_group: [:name, :description])
  end
end
