module Assistant
  module Api
    class StepsController < BaseController
      before_action :set_workflow
      before_action :set_step, only: [:update, :destroy]

      def index
        steps = @workflow.steps.order(:position)
        render json: steps.map { |s| step_json(s) }
      end

      def create
        step = @workflow.steps.build(step_params)
        step.position = (@workflow.steps.maximum(:position) || 0) + 1
        if step.save
          render json: step_json(step), status: :created
        else
          render json: { errors: step.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        if @step.update(step_params)
          render json: step_json(@step)
        else
          render json: { errors: @step.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        @step.destroy
        head :no_content
      end

      def reorder
        reorder_params = params.require(:steps)
        ActiveRecord::Base.transaction do
          reorder_params.each do |item|
            @workflow.steps.find(item[:id]).update!(position: item[:position].to_i)
          end
        end
        render json: { ok: true }
      rescue ActiveRecord::RecordNotFound => e
        render json: { error: e.message }, status: :not_found
      end

      private

      def set_workflow
        project = Project.find(params[:project_id])
        @workflow = project.workflows.find(params[:workflow_id])
      end

      def set_step
        @step = @workflow.steps.find(params[:id])
      end

      def step_params
        params.permit(:name, :step_type, :body, :position, :timeout, :max_retries, :skill_id, config: {})
      end

      def step_json(step)
        {
          id: step.id,
          name: step.name,
          step_type: step.step_type,
          position: step.position,
          workflow_id: step.workflow_id
        }
      end
    end
  end
end
