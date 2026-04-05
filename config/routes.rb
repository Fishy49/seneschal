Rails.application.routes.draw do
  root "dashboard#index"

  # Authentication
  get  "login",    to: "sessions#new"
  post "login",    to: "sessions#create"
  delete "logout", to: "sessions#destroy"
  get  "register", to: "registrations#new"
  post "register", to: "registrations#create"

  # Two-factor authentication
  get  "two_factor",         to: "two_factor#new",     as: :new_two_factor
  post "two_factor",         to: "two_factor#create",  as: :two_factor
  get  "two_factor/setup",   to: "two_factor#setup",   as: :setup_two_factor
  post "two_factor/confirm", to: "two_factor#confirm", as: :confirm_two_factor
  post "two_factor/disable", to: "two_factor#disable", as: :disable_two_factor

  # Account
  get   "account", to: "account#edit"
  patch "account", to: "account#update"

  # Setup / integrations
  get  "setup",              to: "setup#index"
  post "setup/check_claude", to: "setup#check_claude", as: :check_claude_setup
  post "setup/check_gh",     to: "setup#check_gh",     as: :check_gh_setup

  resources :projects do
    member do
      post :clone
    end
    resources :workflows do
      member do
        post :trigger
      end
      resources :steps, only: %i[new create edit update destroy] do
        member do
          patch :move
        end
      end
    end
  end

  resources :skills

  resources :pipeline_tasks, path: "tasks" do
    member do
      post :execute
      patch :mark_ready
    end
  end

  resources :runs, only: %i[index show] do
    member do
      post :stop
      post :resume
      post :retry_from
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
