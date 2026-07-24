class ActivityController < ApplicationController
  PER_PAGE = 50

  def index
    @page = [params[:page].to_i, 1].max
    @events = Event.includes(:user, :subject).recent
                   .offset((@page - 1) * PER_PAGE).limit(PER_PAGE + 1)
                   .to_a

    # One extra row is fetched purely to know whether a next page exists.
    @has_next_page = @events.size > PER_PAGE
    @events = @events.first(PER_PAGE)
  end
end
