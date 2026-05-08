Rails.application.routes.draw do
  root "dashboard#index"

  # Initial admin setup (fresh install only)
  get  "setup/admin", to: "registrations#new", as: :new_admin_setup
  post "setup/admin", to: "registrations#create", as: :admin_setup

  # Authentication
  get  "login",    to: "sessions#new"
  post "login",    to: "sessions#create"
  delete "logout", to: "sessions#destroy"

  # Two-factor authentication
  get  "two_factor",         to: "two_factor#new",     as: :new_two_factor
  post "two_factor",         to: "two_factor#create",  as: :two_factor
  get  "two_factor/setup",   to: "two_factor#setup",   as: :setup_two_factor
  post "two_factor/confirm", to: "two_factor#confirm", as: :confirm_two_factor
  post "two_factor/disable", to: "two_factor#disable", as: :disable_two_factor

  # Invite acceptance (public)
  get   "invite/:token", to: "invites#show", as: :accept_invite
  patch "invite/:token", to: "invites#update"

  # Account
  get   "account", to: "account#edit"
  patch "account", to: "account#update"

  # User management (admin only)
  resources :users, only: [:index, :new, :create, :destroy] do
    member do
      post :reset_invite
    end
  end

  # Setup / integrations
  get   "setup",                    to: "setup#index"
  post  "setup/check_claude",       to: "setup#check_claude",       as: :check_claude_setup
  post  "setup/check_gh",           to: "setup#check_gh",           as: :check_gh_setup
  patch "setup/allowed_tools",      to: "setup#update_allowed_tools", as: :update_allowed_tools_setup

  resources :projects do
    member do
      post :clone
      get :repo_status
      post :import_skills
    end
    resource :code_map, only: [:show] do
      post :generate
      get :status
      get :search
      post :suggestions
    end
    resources :workflows do
      member do
        post :trigger
      end
      resource :copy, only: [:new, :create], controller: "workflow_copies"
      resources :steps, only: [:new, :create, :edit, :update, :destroy] do
        collection do
          patch :reorder
          get :available_variables
          get :produces_suggestions
        end
        member do
          patch :move
        end
      end
    end
  end

  resources :skills
  resources :json_schemas
  resources :project_groups
  resources :step_templates, path: "templates", only: [:index, :destroy]

  # Data management (admin only)
  get  "data",        to: "data#index",  as: :data_management
  get  "data/export", to: "data#export", as: :data_export
  post "data/import", to: "data#import", as: :data_import

  post "tasks/format_body",     to: "pipeline_tasks#format_body",     as: :format_task_body
  get  "tasks/remote_branches", to: "pipeline_tasks#remote_branches", as: :remote_task_branches
  resources :pipeline_tasks, path: "tasks" do
    member do
      post :execute
      patch :mark_ready
      patch :archive
      patch :unarchive
    end
  end

  resources :runs, only: [:index, :show] do
    member do
      post :stop
      post :resume
      post :retry_from
      post :follow_up
      post :approve
      post :reject
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
