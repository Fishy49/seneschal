class StepTemplatesController < ApplicationController
  def index
    @templates = StepTemplate.ordered.includes(skill: [:project, :project_group])
  end

  def destroy
    StepTemplate.find(params[:id]).destroy
    redirect_to step_templates_path, notice: "Template deleted."
  end
end
