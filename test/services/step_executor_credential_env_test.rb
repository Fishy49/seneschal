require "test_helper"

# The extra_env seam (3.6): a launcher's stored credentials reach the spawned
# process, and an empty overlay changes nothing about today's behaviour.
class StepExecutorCredentialEnvTest < ActiveSupport::TestCase
  setup do
    @project = projects(:seneschal)
    FileUtils.mkdir_p(@project.local_path)
    @step = steps(:skill_step)
  end

  def env_for(extra_env, context = {})
    StepExecutor.new(@step, context, @project.local_path, extra_env: extra_env).send(:env_vars)
  end

  test "an empty overlay leaves env_vars byte-identical" do
    context = { "task_title" => "Ship it", "branch_name" => "feature/x" }

    baseline = StepExecutor.new(@step, context, @project.local_path).send(:env_vars)
    assert_equal baseline, env_for({}, context)
    assert_equal baseline, env_for(nil, context)
  end

  test "the overlay reaches env_vars" do
    env = env_for({ "GH_TOKEN" => "ghp_abc", "ANTHROPIC_API_KEY" => "sk-ant-abc" })

    assert_equal "ghp_abc", env["GH_TOKEN"]
    assert_equal "sk-ant-abc", env["ANTHROPIC_API_KEY"]
  end

  test "the overlay is merged last and beats a colliding context variable" do
    env = env_for({ "GH_TOKEN" => "the-users-token" }, { "gh_token" => "from-run-context" })

    assert_equal "the-users-token", env["GH_TOKEN"],
                 "run context must never be able to override a launcher's credential"
  end

  test "the overlay does not disturb the standard variables" do
    env = env_for({ "GH_TOKEN" => "ghp_abc" }, { "task_title" => "Ship it" })

    assert_equal @project.local_path.to_s, env["REPO_PATH"]
    assert_equal "Ship it", env["TASK_TITLE"]
  end

  test "the overlay reaches the runner kwargs used for skill and prompt steps" do
    executor = StepExecutor.new(@step, {}, @project.local_path, extra_env: { "GH_TOKEN" => "ghp_abc" })
    kwargs = executor.send(:runner_call_kwargs, prompt: "hi", stream: false)

    assert_equal "ghp_abc", kwargs[:env]["GH_TOKEN"]
  end

  # The pr and ci_check paths shell out to `gh` through the same env_vars
  # helper, since PrCreator is mixed into StepExecutor rather than being a
  # separate object with its own environment.
  test "the gh spawn paths share the same env_vars method" do
    assert StepExecutor.include?(StepExecutor::PrCreator)
    assert_equal "ghp_abc", env_for({ "GH_TOKEN" => "ghp_abc" })["GH_TOKEN"]
  end

  test "credentials never land in the run context or the resolved input context" do
    context = { "task_title" => "Ship it" }
    executor = StepExecutor.new(@step, context, @project.local_path,
                                resolved_input_context: "some instructions",
                                extra_env: { "GH_TOKEN" => "ghp_secret" })
    executor.send(:env_vars)

    assert_no_match(/ghp_secret/, context.to_json)
    assert_no_match(/ghp_secret/, executor.instance_variable_get(:@resolved_input_context).to_s)
  end
end
