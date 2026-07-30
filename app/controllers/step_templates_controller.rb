class StepTemplatesController < ApplicationController
  before_action :set_template, only: [:show, :edit, :update, :destroy]

  def index
    @templates = StepTemplate.ordered.includes(skill: :project)
    @projects = Project.order(:name)
  end

  def show; end

  def edit; end

  # Only the labelling is editable. The configuration is captured from a step
  # that already works; hand-editing it here would let it drift from anything
  # that ever ran.
  def update
    if @template.update(template_params)
      redirect_to @template, notice: "Template updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @template.destroy
    redirect_to step_templates_path, notice: "Template deleted."
  end

  private

  def set_template
    @template = StepTemplate.find(params.expect(:id))
  end

  def template_params
    params.expect(step_template: [:name, :description])
  end
end
