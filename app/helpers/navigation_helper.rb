module NavigationHelper
  # Controllers that have no top-level slot of their own still light up the
  # section they live under.
  NAV_SECTIONS = {
    "dashboard" => :home,
    "runs" => :runs,
    "shared_runs" => :runs,
    "projects" => :projects,
    "pipeline_tasks" => :projects,
    "workflows" => :projects,
    "steps" => :projects,
    "code_maps" => :projects,
    "workflow_copies" => :projects,
    "workflow_imports" => :projects,
    "skills" => :library,
    "json_schemas" => :library,
    "step_templates" => :library,
    "skill_repos" => :library,
    "activity" => :activity,
    "users" => :admin,
    "invites" => :admin,
    "project_groups" => :admin,
    "data" => :admin,
    "admin_settings" => :admin,
    "setup" => :admin
  }.freeze

  LIBRARY_TABS = [
    { label: "Skills", controller: "skills", path: :skills_path },
    { label: "Output schemas", controller: "json_schemas", path: :json_schemas_path },
    { label: "Templates", controller: "step_templates", path: :step_templates_path },
    { label: "Skill repos", controller: "skill_repos", path: :skill_repos_path, admin: true }
  ].freeze

  ADMIN_TABS = [
    { label: "Users", controller: "users", path: :users_path },
    { label: "Groups", controller: "project_groups", path: :project_groups_path },
    { label: "Server settings", controller: "admin_settings", path: :admin_settings_path },
    { label: "Data", controller: "data", path: :data_management_path },
    { label: "Health checks", controller: "setup", path: :setup_path }
  ].freeze

  def nav_section
    NAV_SECTIONS[controller_name]
  end

  def nav_link_classes(section)
    state = if nav_section == section
              "bg-surface-input text-content"
            else
              "text-content-muted hover:bg-surface-input hover:text-content"
            end
    "block px-3 py-2 rounded-lg text-sm transition-colors #{state}"
  end

  def nav_sublink_classes(controller)
    state = if controller_name == controller
              "text-content"
            else
              "text-content-muted opacity-80 hover:opacity-100 hover:text-content"
            end
    "block px-3 py-1 rounded-lg text-[0.8125rem] transition-colors #{state}"
  end

  def nav_tab_classes(active)
    state = active ? "border-accent text-content" : "border-transparent text-content-muted hover:text-content"
    "px-3 py-2 -mb-px border-b-2 text-sm transition-colors #{state}"
  end

  def nav_tabs_for(tabs)
    tabs.reject { |tab| tab[:admin] && !current_user&.admin? }
  end
end
