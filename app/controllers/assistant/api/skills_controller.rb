module Assistant
  module Api
    class SkillsController < BaseController
      before_action :set_skill, only: [:show, :update, :destroy]

      def index
        skills = Skill.includes(:project).order(:name)
        render json: skills.map { |s| skill_json(s) }
      end

      def show
        render json: skill_json(@skill)
      end

      def create
        skill = Skill.new(skill_params)
        if skill.save
          render json: skill_json(skill), status: :created
        else
          render json: { errors: skill.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        if @skill.update(skill_params)
          render json: skill_json(@skill)
        else
          render json: { errors: @skill.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        @skill.destroy
        head :no_content
      end

      private

      def set_skill
        @skill = Skill.find(params[:id])
      end

      def skill_params
        params.permit(:name, :description, :body, :project_id)
      end

      def skill_json(skill)
        {
          id: skill.id,
          name: skill.name,
          description: skill.description,
          body: skill.body,
          project_id: skill.project_id,
          shared: skill.shared?,
          path: "/skills/#{skill.id}"
        }
      end
    end
  end
end
