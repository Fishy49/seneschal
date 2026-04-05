# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_04_05_044555) do
  create_table "pipeline_tasks", force: :cascade do |t|
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.string "kind", default: "feature", null: false
    t.integer "project_id", null: false
    t.string "status", default: "draft", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.integer "workflow_id"
    t.index ["project_id"], name: "index_pipeline_tasks_on_project_id"
    t.index ["workflow_id"], name: "index_pipeline_tasks_on_workflow_id"
  end

  create_table "projects", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "local_path", null: false
    t.string "name", null: false
    t.string "repo_status", default: "not_cloned", null: false
    t.string "repo_url", null: false
    t.datetime "updated_at", null: false
  end

  create_table "run_steps", force: :cascade do |t|
    t.integer "attempt", default: 1, null: false
    t.string "claude_session_id"
    t.datetime "created_at", null: false
    t.float "duration"
    t.text "error_output"
    t.integer "exit_code"
    t.datetime "finished_at"
    t.text "output"
    t.integer "position"
    t.text "resolved_input_context"
    t.integer "run_id", null: false
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.integer "step_id", null: false
    t.json "stream_log"
    t.datetime "updated_at", null: false
    t.index ["run_id"], name: "index_run_steps_on_run_id"
    t.index ["step_id"], name: "index_run_steps_on_step_id"
  end

  create_table "runs", force: :cascade do |t|
    t.json "context", default: {}, null: false
    t.datetime "created_at", null: false
    t.text "error_message"
    t.datetime "finished_at"
    t.json "input", default: {}, null: false
    t.integer "pipeline_task_id"
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.integer "workflow_id", null: false
    t.index ["pipeline_task_id"], name: "index_runs_on_pipeline_task_id"
    t.index ["workflow_id"], name: "index_runs_on_workflow_id"
  end

  create_table "settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.text "value"
    t.index ["key"], name: "index_settings_on_key", unique: true
  end

  create_table "skills", force: :cascade do |t|
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.integer "project_id"
    t.datetime "updated_at", null: false
    t.index ["project_id"], name: "index_skills_on_project_id"
  end

  create_table "steps", force: :cascade do |t|
    t.text "body"
    t.json "config", default: {}, null: false
    t.datetime "created_at", null: false
    t.boolean "injectable_only", default: false, null: false
    t.text "input_context"
    t.integer "max_retries", default: 0, null: false
    t.string "name", null: false
    t.integer "position", null: false
    t.integer "skill_id"
    t.string "step_type", null: false
    t.integer "timeout", default: 600, null: false
    t.datetime "updated_at", null: false
    t.integer "workflow_id", null: false
    t.index ["skill_id"], name: "index_steps_on_skill_id"
    t.index ["workflow_id"], name: "index_steps_on_workflow_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.boolean "otp_required_for_login", default: false, null: false
    t.string "otp_secret"
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  create_table "workflows", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.integer "project_id", null: false
    t.json "trigger_config"
    t.string "trigger_type", default: "manual", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id"], name: "index_workflows_on_project_id"
  end

  add_foreign_key "pipeline_tasks", "projects"
  add_foreign_key "pipeline_tasks", "workflows"
  add_foreign_key "run_steps", "runs"
  add_foreign_key "run_steps", "steps"
  add_foreign_key "runs", "pipeline_tasks"
  add_foreign_key "runs", "workflows"
  add_foreign_key "skills", "projects"
  add_foreign_key "steps", "skills"
  add_foreign_key "steps", "workflows"
  add_foreign_key "workflows", "projects"
end
