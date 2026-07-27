require "test_helper"

class StepsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:admin)
    @project = projects(:seneschal)
    @workflow = workflows(:deploy)
  end

  test "GET new renders form" do
    get new_project_workflow_step_path(@project, @workflow)
    assert_response :success
  end

  test "POST create skill step" do
    assert_difference "Step.count", 1 do
      post project_workflow_steps_path(@project, @workflow), params: {
        step: {
          name: "New Skill Step",
          step_type: "skill",
          skill_id: skills(:shared_skill).id,
          position: 10,
          timeout: 300,
          max_retries: 0
        }
      }
    end
    assert_redirected_to project_workflow_path(@project, @workflow)
  end

  test "POST create command step" do
    assert_difference "Step.count", 1 do
      post project_workflow_steps_path(@project, @workflow), params: {
        step: {
          name: "New Command",
          step_type: "command",
          body: "echo hello",
          position: 10,
          timeout: 60,
          max_retries: 0
        }
      }
    end
    assert_redirected_to project_workflow_path(@project, @workflow)
  end

  test "POST create without a position appends to the end" do
    last = @workflow.steps.maximum(:position)
    post project_workflow_steps_path(@project, @workflow), params: {
      step: { name: "Appended", step_type: "command", body: "echo hi" }
    }
    assert_equal last + 1, Step.find_by(name: "Appended").position
  end

  test "POST create respects an explicit position" do
    post project_workflow_steps_path(@project, @workflow), params: {
      step: { name: "Placed", step_type: "command", body: "echo hi", position: 1 }
    }
    assert_equal 1, Step.find_by(name: "Placed").position
  end

  test "the step form renders inside the inspector frame" do
    get edit_project_workflow_step_path(@project, @workflow, steps(:skill_step))
    assert_select "turbo-frame#step_inspector"
  end

  test "saving from the inspector refreshes the canvas and the inspector" do
    patch project_workflow_step_path(@project, @workflow, steps(:skill_step)),
          params: { step: { name: "Renamed in place" } },
          as: :turbo_stream
    assert_response :success
    assert_match "workflow_steps", response.body
    assert_match "step_inspector", response.body
    assert_match "Renamed in place", response.body
  end

  test "POST create with invalid params" do
    assert_no_difference "Step.count" do
      post project_workflow_steps_path(@project, @workflow), params: {
        step: { name: "", step_type: "skill", position: 10 }
      }
    end
    assert_response :unprocessable_content
  end

  test "GET edit renders form" do
    get edit_project_workflow_step_path(@project, @workflow, steps(:skill_step))
    assert_response :success
  end

  test "PATCH update" do
    patch project_workflow_step_path(@project, @workflow, steps(:skill_step)), params: {
      step: { name: "Updated Name" }
    }
    assert_redirected_to project_workflow_path(@project, @workflow)
    assert_equal "Updated Name", steps(:skill_step).reload.name
  end

  test "DELETE destroy removes step" do
    step = @workflow.steps.create!(name: "Temp", step_type: "command", body: "echo x", position: 99)
    assert_difference "Step.count", -1 do
      delete project_workflow_step_path(@project, @workflow, step)
    end
    assert_redirected_to project_workflow_path(@project, @workflow)
  end

  test "PATCH move updates position" do
    patch move_project_workflow_step_path(@project, @workflow, steps(:skill_step)), params: { position: 5 }
    assert_redirected_to project_workflow_path(@project, @workflow)
    assert_equal 5, steps(:skill_step).reload.position
  end

  test "POST create with save_as_template creates both step and template" do
    assert_difference ["Step.count", "StepTemplate.count"], 1 do
      post project_workflow_steps_path(@project, @workflow), params: {
        step: {
          name: "Reusable Command",
          step_type: "command",
          body: "make build",
          position: 10,
          timeout: 120,
          max_retries: 1
        },
        save_as_template: "1",
        template_name: "Build Step",
        template_description: "Builds and uploads"
      }
    end
    template = StepTemplate.find_by(name: "Build Step")
    assert_not_nil template
    assert_equal "command", template.step_type
    assert_equal "make build", template.body
    assert_equal 120, template.timeout
    assert_equal "Builds and uploads", template.description
  end

  test "POST create without save_as_template does not create template" do
    assert_no_difference "StepTemplate.count" do
      post project_workflow_steps_path(@project, @workflow), params: {
        step: {
          name: "No Template",
          step_type: "command",
          body: "echo hi",
          position: 10
        }
      }
    end
  end

  test "GET new shows template selector when templates exist" do
    get new_project_workflow_step_path(@project, @workflow)
    assert_response :success
    assert_select "[data-controller*='template-panel']"
  end

  test "manual_approval flag persists on create" do
    assert_difference "Step.count", 1 do
      post project_workflow_steps_path(@project, @workflow), params: {
        step: {
          name: "Approve me",
          step_type: "command",
          body: "echo hi",
          position: 20,
          timeout: 60,
          max_retries: 0,
          manual_approval: "1"
        }
      }
    end
    assert_redirected_to project_workflow_path(@project, @workflow)
    assert Step.find_by(name: "Approve me").manual_approval
  end

  test "manual_approval flag persists on update" do
    patch project_workflow_step_path(@project, @workflow, steps(:command_step)), params: {
      step: { manual_approval: "1" }
    }
    assert steps(:command_step).reload.manual_approval
  end

  test "GET edit shows manual_approval checkbox" do
    get edit_project_workflow_step_path(@project, @workflow, steps(:skill_step))
    assert_response :success
    assert_select "input[type=checkbox][name='step[manual_approval]']"
  end

  test "manual_approval is carried into save_as_template" do
    assert_difference "StepTemplate.count", 1 do
      post project_workflow_steps_path(@project, @workflow), params: {
        step: {
          name: "Approval Template Step",
          step_type: "command",
          body: "echo ok",
          position: 21,
          timeout: 60,
          max_retries: 0,
          manual_approval: "1"
        },
        save_as_template: "1",
        template_name: "Approval Template"
      }
    end
    template = StepTemplate.find_by(name: "Approval Template")
    assert_not_nil template
    assert template.manual_approval
  end

  test "POST create skill step with json_schema_id persists it in config" do
    schema = json_schemas(:person_schema)
    assert_difference "Step.count", 1 do
      post project_workflow_steps_path(@project, @workflow), params: {
        step: {
          name: "Schema Skill",
          step_type: "skill",
          skill_id: skills(:shared_skill).id,
          position: 50,
          timeout: 60,
          max_retries: 0
        },
        json_schema_id: schema.id.to_s
      }
    end
    assert_equal schema.id, Step.last.config["json_schema_id"]
  end

  test "POST create skill step in inherit mode lets skill default schema fill in" do
    schema = json_schemas(:person_schema)
    skill = skills(:shared_skill)
    skill.update!(default_json_schema: schema, default_output_variable: "inherited_var")
    assert_difference "Step.count", 1 do
      post project_workflow_steps_path(@project, @workflow), params: {
        step: {
          name: "Inherit Skill",
          step_type: "skill",
          skill_id: skill.id,
          position: 51,
          timeout: 60,
          max_retries: 0
        },
        # No json_schema_id, no schema_picker_mode (or "inherit"): inheritance fires.
        schema_picker_mode: "inherit"
      }
    end
    assert_equal schema.id, Step.last.config["json_schema_id"]
    assert_equal ["inherited_var"], Step.last.config["produces"]
  end

  test "POST create skill step in override mode with blank schema beats inheritance" do
    schema = json_schemas(:person_schema)
    skill = skills(:shared_skill)
    skill.update!(default_json_schema: schema, default_output_variable: "inherited_var")
    assert_difference "Step.count", 1 do
      post project_workflow_steps_path(@project, @workflow), params: {
        step: {
          name: "Override-None Skill",
          step_type: "skill",
          skill_id: skill.id,
          position: 52,
          timeout: 60,
          max_retries: 0
        },
        # Explicit override → None must stick instead of inheriting the skill default.
        schema_picker_mode: "override",
        json_schema_id: ""
      }
    end
    assert_nil Step.last.config["json_schema_id"]
  end

  test "GET edit renders produces-input controller" do
    get edit_project_workflow_step_path(@project, @workflow, steps(:skill_step))
    assert_response :success
    assert_match "data-controller=\"produces-input\"", response.body
    assert_select "input[type=hidden][name=produces]"
  end

  test "GET produces_suggestions returns global variables and existing produces" do
    steps(:skill_step).update!(config: { "produces" => ["custom_var"] })
    get produces_suggestions_project_workflow_steps_path(@project, @workflow)
    assert_response :success
    data = response.parsed_body
    Step::GLOBAL_VARIABLES.each do |gv|
      assert_includes data["suggestions"], gv
    end
    assert_includes data["suggestions"], "custom_var"
  end

  test "POST create skill step with schema and schema_output_variable persists produces as single-element array" do
    schema = json_schemas(:person_schema)
    assert_difference "Step.count", 1 do
      post project_workflow_steps_path(@project, @workflow), params: {
        step: {
          name: "Schema Skill",
          step_type: "skill",
          skill_id: skills(:shared_skill).id,
          position: 51,
          timeout: 60,
          max_retries: 0
        },
        json_schema_id: schema.id.to_s,
        schema_output_variable: "person_payload",
        produces: "alpha,beta"
      }
    end
    step = Step.last
    assert_equal schema.id, step.config["json_schema_id"]
    assert_equal ["person_payload"], step.config["produces"]
  end

  test "PATCH update wipes existing produces when json_schema_id is set" do
    schema = json_schemas(:person_schema)
    step = steps(:skill_step)
    step.update!(config: { "produces" => ["alpha", "beta"] })

    patch project_workflow_step_path(@project, @workflow, step), params: {
      step: {
        name: step.name,
        step_type: "skill",
        skill_id: step.skill_id,
        position: step.position,
        timeout: step.timeout,
        max_retries: step.max_retries
      },
      json_schema_id: schema.id.to_s,
      schema_output_variable: "person_payload",
      produces: "alpha,beta"
    }

    step.reload
    assert_equal ["person_payload"], step.config["produces"]
  end

  test "POST create context_fetch step with project_file persists path and json_schema_id" do
    schema = json_schemas(:person_schema)
    assert_difference "Step.count", 1 do
      post project_workflow_steps_path(@project, @workflow), params: {
        step: {
          name: "Read settings",
          step_type: "context_fetch",
          position: 80,
          timeout: 30,
          max_retries: 0
        },
        fetch_method: "project_file",
        fetch_path: "config/feature_flags.json",
        fetch_context_key: "flags",
        fetch_json_schema_id: schema.id.to_s
      }
    end
    cfg = Step.last.config
    assert_equal "project_file", cfg["method"]
    assert_equal "config/feature_flags.json", cfg["path"]
    assert_equal "flags", cfg["context_key"]
    assert_equal schema.id, cfg["json_schema_id"]
    assert_nil cfg["url"]
  end

  test "POST create persists queries from form into config" do
    assert_difference "Step.count", 1 do
      post project_workflow_steps_path(@project, @workflow), params: {
        step: {
          name: "Querying step",
          step_type: "skill",
          skill_id: skills(:shared_skill).id,
          position: 90,
          timeout: 60,
          max_retries: 0
        },
        queries: ["foundation"]
      }
    end
    assert_equal ["foundation"], Step.last.config["queries"]
    assert_equal ["foundation"], Step.last.queries
  end

  test "POST create pr step persists declared fields into config" do
    assert_difference "Step.count", 1 do
      post project_workflow_steps_path(@project, @workflow), params: {
        step: {
          name: "Open PR",
          step_type: "pr",
          position: 70,
          timeout: 60,
          max_retries: 0
        },
        pr_title: "feat: ${task_title}",
        pr_body: "## Summary\n\n${task_body}",
        pr_base: "main",
        pr_draft: "1",
        pr_reviewers: "alice, bob",
        pr_labels: "feature, needs-review",
        pr_assignees: "alice"
      }
    end

    cfg = Step.last.config
    assert_equal "feat: ${task_title}", cfg["title"]
    assert_equal "## Summary\n\n${task_body}", cfg["body"]
    assert_equal "main", cfg["base"]
    assert_equal true, cfg["draft"]
    assert_equal ["alice", "bob"], cfg["reviewers"]
    assert_equal ["feature", "needs-review"], cfg["labels"]
    assert_equal ["alice"], cfg["assignees"]
  end

  test "POST create pr step preserves draft=false when checkbox unchecked" do
    assert_difference "Step.count", 1 do
      post project_workflow_steps_path(@project, @workflow), params: {
        step: {
          name: "Ready PR",
          step_type: "pr",
          position: 71,
          timeout: 60,
          max_retries: 0
        },
        pr_title: "fix: thing",
        pr_draft: "0"
      }
    end
    assert_equal false, Step.last.config["draft"]
  end

  test "POST create pr step rejects missing title" do
    assert_no_difference "Step.count" do
      post project_workflow_steps_path(@project, @workflow), params: {
        step: {
          name: "Bad PR",
          step_type: "pr",
          position: 72,
          timeout: 60,
          max_retries: 0
        },
        pr_title: ""
      }
    end
    assert_response :unprocessable_content
  end

  # Regression: editing an inherit-mode step and saving without changes used
  # to wipe both produces and json_schema_id, because the controller's
  # claude_schema_mode? check only fired when json_schema_id was already in
  # permitted[:config] — which inherit-mode deliberately leaves absent.
  test "PATCH update preserves produces and json_schema_id when saving an inherit-mode step unchanged" do
    schema = json_schemas(:person_schema)
    skill = skills(:shared_skill)
    skill.update!(default_json_schema: schema, default_output_variable: "foundation")
    step = steps(:skill_step)
    step.update!(skill: skill, config: { "json_schema_id" => schema.id, "produces" => ["foundation"] })

    patch project_workflow_step_path(@project, @workflow, step), params: {
      step: {
        name: step.name,
        step_type: "skill",
        skill_id: skill.id,
        position: step.position,
        timeout: step.timeout,
        max_retries: step.max_retries
      },
      # Form in inherit mode: badge visible, picker hidden so json_schema_id="",
      # schema_output_variable is the canonical produces source, multi-tag is
      # hidden so produces="" comes through empty.
      schema_picker_mode: "inherit",
      json_schema_id: "",
      schema_output_variable: "foundation",
      produces: ""
    }

    step.reload
    assert_equal ["foundation"], step.config["produces"]
    assert_equal schema.id, step.config["json_schema_id"]
  end

  test "PATCH update in inherit mode honors an edited schema_output_variable" do
    schema = json_schemas(:person_schema)
    skill = skills(:shared_skill)
    skill.update!(default_json_schema: schema, default_output_variable: "foundation")
    step = steps(:skill_step)
    step.update!(skill: skill, config: { "json_schema_id" => schema.id, "produces" => ["foundation"] })

    patch project_workflow_step_path(@project, @workflow, step), params: {
      step: {
        name: step.name, step_type: "skill", skill_id: skill.id,
        position: step.position, timeout: step.timeout, max_retries: step.max_retries
      },
      schema_picker_mode: "inherit",
      json_schema_id: "",
      schema_output_variable: "renamed_var",
      produces: ""
    }

    step.reload
    assert_equal ["renamed_var"], step.config["produces"]
    assert_equal schema.id, step.config["json_schema_id"]
  end

  test "PATCH update from inherit to explicit None drops the schema" do
    schema = json_schemas(:person_schema)
    skill = skills(:shared_skill)
    skill.update!(default_json_schema: schema, default_output_variable: "foundation")
    step = steps(:skill_step)
    step.update!(skill: skill, config: { "json_schema_id" => schema.id, "produces" => ["foundation"] })

    patch project_workflow_step_path(@project, @workflow, step), params: {
      step: {
        name: step.name, step_type: "skill", skill_id: skill.id,
        position: step.position, timeout: step.timeout, max_retries: step.max_retries
      },
      schema_picker_mode: "override",
      json_schema_id: "",
      schema_output_variable: "",
      produces: "alpha,beta"
    }

    step.reload
    assert_nil step.config["json_schema_id"]
    assert_equal ["alpha", "beta"], step.config["produces"]
  end

  test "GET edit on an inherit-mode step shows the schema output variable input populated" do
    schema = json_schemas(:person_schema)
    skill = skills(:shared_skill)
    skill.update!(default_json_schema: schema, default_output_variable: "foundation")
    step = steps(:skill_step)
    step.update!(skill: skill, config: { "json_schema_id" => schema.id, "produces" => ["foundation"] })

    get edit_project_workflow_step_path(@project, @workflow, step)
    assert_response :success
    assert_select "input[name=schema_output_variable][value=foundation]"
    assert_select "input[type=hidden][name=schema_picker_mode][value=inherit]"
  end

  test "POST create persists produces as array" do
    assert_difference "Step.count", 1 do
      post project_workflow_steps_path(@project, @workflow), params: {
        step: {
          name: "Producer",
          step_type: "command",
          body: "echo hi",
          position: 60,
          timeout: 30,
          max_retries: 0
        },
        produces: "alpha,beta"
      }
    end
    assert_equal ["alpha", "beta"], Step.last.config["produces"]
    assert_equal ["alpha", "beta"], Step.last.produces
  end

  # The controller's config builders are the contract between the form and the
  # executor. These pin every key each type writes, so decomposing the view
  # cannot quietly drop one.
  def created_step(params)
    post project_workflow_steps_path(@project, @workflow), params: params
    assert_response :redirect
    Step.order(:id).last
  end

  test "a skill step round-trips every model and tool key" do
    step = created_step(
      step: { name: "Round trip skill", step_type: "skill", skill_id: skills(:project_skill).id },
      skill_model: "claude-opus-4-7", skill_effort: "high", skill_max_turns: "12",
      skill_allowed_tools: "Bash(git *),Read", skill_preview_assets: "1",
      skill_validation_max_attempts: "5", schema_picker_mode: "override", json_schema_id: "",
      skill_context_projects: [projects(:other_project).id.to_s],
      produces: "plan", consumes: ["task_title"]
    )

    assert_equal "claude-opus-4-7", step.config["model"]
    assert_equal "high", step.config["effort"]
    assert_equal 12, step.config["max_turns"]
    assert_equal "Bash(git *),Read", step.config["allowed_tools"]
    assert_equal true, step.config["preview_assets"]
    assert_equal 5, step.config["validation_max_attempts"]
    assert_equal [projects(:other_project).id], step.config["context_projects"]
    assert_equal ["plan"], step.config["produces"]
    assert_equal ["task_title"], step.config["consumes"]
  end

  test "a shell step round-trips its command" do
    step = created_step(step: { name: "Round trip shell", step_type: "command", body: "npm run build" })
    assert_equal "command", step.step_type
    assert_equal "npm run build", step.body
  end

  test "a ci_check step round-trips every watcher key" do
    step = created_step(
      step: { name: "Round trip ci", step_type: "ci_check" },
      ci_mode: "workflow", ci_workflow: "test.yml", ci_ref: "${branch_name}", ci_trigger: "1",
      ci_poll_interval: "45", ci_max_log_chars: "5000", ci_log_from: "beginning"
    )

    assert_equal "workflow", step.config["mode"]
    assert_equal "test.yml", step.config["workflow"]
    assert_equal "${branch_name}", step.config["ref"]
    assert_equal true, step.config["trigger"]
    assert_equal 45, step.config["poll_interval"]
    assert_equal 5000, step.config["max_log_chars"]
    assert_equal "beginning", step.config["log_from"]
  end

  test "a context_fetch step round-trips both methods" do
    url_step = created_step(
      step: { name: "Round trip fetch url", step_type: "context_fetch" },
      fetch_method: "url", fetch_url: "https://example.com/data", fetch_context_key: "external"
    )
    assert_equal "url", url_step.config["method"]
    assert_equal "https://example.com/data", url_step.config["url"]
    assert_equal "external", url_step.config["context_key"]
    assert_equal "external", url_step.config["capture_output"]

    file_step = created_step(
      step: { name: "Round trip fetch file", step_type: "context_fetch" },
      fetch_method: "project_file", fetch_path: "config/app.json",
      fetch_json_schema_id: json_schemas(:simple_schema).id.to_s, fetch_context_key: "app_config"
    )
    assert_equal "project_file", file_step.config["method"]
    assert_equal "config/app.json", file_step.config["path"]
    assert_equal json_schemas(:simple_schema).id, file_step.config["json_schema_id"]
  end

  test "a pr step round-trips every pull request key" do
    step = created_step(
      step: { name: "Round trip pr", step_type: "pr" },
      pr_title: "feat: ${task_title}", pr_body: "## Changes", pr_base: "develop", pr_branch: "feature/x",
      pr_draft: "1", pr_clean: "1", pr_reviewers: "octocat, my-org/devs",
      pr_labels: "enhancement", pr_assignees: "dev-one"
    )

    assert_equal "feat: ${task_title}", step.config["title"]
    assert_equal "## Changes", step.config["body"]
    assert_equal "develop", step.config["base"]
    assert_equal "feature/x", step.config["branch"]
    assert_equal true, step.config["draft"]
    assert_equal true, step.config["clean"]
    assert_equal ["octocat", "my-org/devs"], step.config["reviewers"]
    assert_equal ["enhancement"], step.config["labels"]
    assert_equal ["dev-one"], step.config["assignees"]
  end

  test "a self_review step can be created from the UI" do
    step = created_step(
      step: { name: "Review my work", step_type: "self_review" },
      review_base_ref: "develop", review_focus: "Check the error handling."
    )

    assert_equal "self_review", step.step_type
    assert_equal "develop", step.config["base_ref"]
    assert_equal "Check the error handling.", step.config["focus"]
  end

  test "a self_review step with no settings stores no keys" do
    step = created_step(step: { name: "Plain review", step_type: "self_review" }, review_base_ref: "", review_focus: "")
    assert_empty step.config.slice("base_ref", "focus")
  end

  test "on_fail recovery round-trips including reopen instructions" do
    step = created_step(
      step: { name: "Recovers", step_type: "command", body: "true" },
      on_fail_type: "reopen_previous", on_fail_max_rounds: "2",
      on_fail_instructions: "Look at the lockfile."
    )

    assert_equal "reopen_previous", step.config.dig("on_fail_action", "type")
    assert_equal 2, step.config.dig("on_fail_action", "max_rounds")
    assert_equal "Look at the lockfile.", step.config.dig("on_fail_action", "instructions")
  end

  test "each type renders only its own fields" do
    get new_project_workflow_step_path(@project, @workflow), params: { step_type: "pr" }
    assert_select "input#pr_title"
    assert_select "select#ci_mode", count: 0
    assert_select "select#skill_model", count: 0

    get new_project_workflow_step_path(@project, @workflow), params: { step_type: "ci_check" }
    assert_select "select#ci_mode"
    assert_select "input#pr_title", count: 0
  end

  test "the form no longer asks for a position" do
    get new_project_workflow_step_path(@project, @workflow)
    assert_select "input[name='step[position]']", count: 0
  end

  test "a script step edits as a shell step" do
    script = @workflow.steps.create!(name: "Legacy script", step_type: "script", body: "./build.sh", position: 99)
    get edit_project_workflow_step_path(@project, @workflow, script)
    assert_select "textarea[name='step[body]']"
    assert_select "select[name='step[step_type]'] option[value='script']", count: 0
  end

  test "editing with a step_type param previews the other type without saving" do
    step = steps(:skill_step)
    get edit_project_workflow_step_path(@project, @workflow, step), params: { step_type: "pr" }
    assert_select "input#pr_title"
    assert_equal "skill", step.reload.step_type
  end

  test "new with a template_id applies the whole captured config" do
    template = StepTemplate.create!(
      name: "Captured", step_type: "ci_check", timeout: 900, max_retries: 4,
      input_context: "Extra guidance", manual_approval: true,
      config: { "mode" => "workflow", "workflow" => "ci.yml", "queries" => ["plan"],
                "context_projects" => [projects(:other_project).id],
                "on_fail_action" => { "type" => "reopen_previous", "instructions" => "Retry it." } }
    )

    get new_project_workflow_step_path(@project, @workflow), params: { template_id: template.id }
    assert_select "input[name='step[name]'][value=?]", "Captured"
    assert_select "input#ci_workflow[value=?]", "ci.yml"
    assert_select "input[name='step[timeout]'][value=?]", "900"
    assert_select "textarea#on_fail_instructions", text: "Retry it."
  end
end
