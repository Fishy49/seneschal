module Assistant
  module Api
    class ProjectsController < BaseController
      before_action :set_project, only: [:show, :update]

      def index
        projects = Project.order(:name)
        render json: projects.map { |p| project_json(p) }
      end

      def show
        render json: project_json(@project)
      end

      def create
        project = Project.new(project_params)
        if project.save
          render json: project_json(project), status: :created
        else
          render json: { errors: project.errors.full_messages }, status: :unprocessable_content
        end
      end

      def update
        if @project.update(project_params)
          render json: project_json(@project)
        else
          render json: { errors: @project.errors.full_messages }, status: :unprocessable_content
        end
      end

      private

      def set_project
        @project = Project.find(params[:id])
      end

      def project_params
        params.permit(:name, :description, :repo_url, :local_path)
      end

      def project_json(project)
        {
          id: project.id,
          name: project.name,
          description: project.description,
          repo_url: project.repo_url,
          repo_status: project.repo_status,
          path: "/projects/#{project.id}"
        }
      end
    end
  end
end
