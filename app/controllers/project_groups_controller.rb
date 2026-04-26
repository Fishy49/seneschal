class ProjectGroupsController < ApplicationController
  before_action :set_group, only: [:edit, :update, :destroy]

  def index
    @groups = ProjectGroup.ordered.includes(:projects)
  end

  def new
    @group = ProjectGroup.new
  end

  def edit; end

  def create
    @group = ProjectGroup.new(group_params)
    if @group.save
      redirect_to project_groups_path, notice: "Group created."
    else
      render :new, status: :unprocessable_content
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
