class AddConfigToWorkflows < ActiveRecord::Migration[8.1]
  # Workflow-level configuration grab bag. First use: a `runner` key
  # that overrides Setting["default_runner"] for every step in this
  # workflow — handy for "this workflow uses structured outputs, route
  # it through the SDK" without per-step config noise.
  def change
    add_column :workflows, :config, :json, default: {}, null: false
  end
end
