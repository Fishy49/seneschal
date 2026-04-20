module Assistant
  module Api
    class PipelineTasksController < BaseController
      before_action :set_task, only: [:show, :update, :destroy]

      def index
        tasks = PipelineTask.order(created_at: :desc)
        render json: tasks.map { |t| task_json(t) }
      end

      def show
        render json: task_json(@task)
      end

      def create
        task = PipelineTask.new(task_params)
        if task.save
          render json: task_json(task), status: :created
        else
          render json: { errors: task.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        if @task.update(task_params)
          render json: task_json(@task)
        else
          render json: { errors: @task.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        @task.destroy
        head :no_content
      end

      private

      def set_task
        @task = PipelineTask.find(params[:id])
      end

      def task_params
        params.permit(:title, :body, :kind, :status, :project_id, :workflow_id)
      end

      def task_json(task)
        {
          id: task.id,
          title: task.title,
          body: task.body,
          kind: task.kind,
          status: task.status,
          project_id: task.project_id,
          workflow_id: task.workflow_id,
          path: "/tasks/#{task.id}"
        }
      end
    end
  end
end
