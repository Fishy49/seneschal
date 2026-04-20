module Assistant
  module Api
    class PageContextsController < BaseController
      def show
        path = params[:path].to_s
        context = AssistantPageContext.summarize(path)
        render json: context
      end
    end
  end
end
