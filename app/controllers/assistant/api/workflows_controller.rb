module Assistant
  module Api
    class WorkflowsController < BaseController
      before_action :set_project
      before_action :set_workflow, only: [:show, :update, :destroy, :trigger]

      def index
        workflows = @project.workflows.order(:name)
        render json: workflows.map { |w| workflow_json(w) }
      end

      def show
        render json: workflow_json(@workflow)
      end

      def create
        workflow = @project.workflows.build(workflow_params)
        if workflow.save
          render json: workflow_json(workflow), status: :created
        else
          render json: { errors: workflow.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        if @workflow.update(workflow_params)
          render json: workflow_json(@workflow)
        else
          render json: { errors: @workflow.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        @workflow.destroy
        head :no_content
      end

      def trigger
        run = @workflow.runs.create!(input: trigger_input_params)
        ExecuteRunJob.perform_later(run)
        render json: { run_id: run.id, path: "/runs/#{run.id}" }, status: :created
      end

      private

      def set_project
        @project = Project.find(params[:project_id])
      end

      def set_workflow
        @workflow = @project.workflows.find(params[:id])
      end

      def workflow_params
        params.permit(:name, :description, :trigger_type)
      end

      def trigger_input_params
        params.permit(input: {}).to_h.fetch("input", {})
      end

      def workflow_json(workflow)
        {
          id: workflow.id,
          name: workflow.name,
          description: workflow.description,
          trigger_type: workflow.trigger_type,
          project_id: workflow.project_id,
          steps_count: workflow.steps.size,
          path: "/projects/#{workflow.project_id}/workflows/#{workflow.id}"
        }
      end
    end
  end
end
