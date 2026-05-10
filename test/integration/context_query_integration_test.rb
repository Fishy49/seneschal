require "test_helper"
require "open3"

# Verifies the full bridge between StepExecutor and bin/seneschal-context:
# the env vars the executor exports for a queryable step are sufficient for
# the wrapper subprocess to (a) read the run's context from SQLite, (b) pipe
# the right variable through jq, and (c) write a log row that attaches to
# the correct run_step. Non-transactional because the wrapper runs in a
# separate process and needs to see committed data.
class ContextQueryIntegrationTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  WRAPPER = Rails.root.join("bin/seneschal-context").to_s

  setup { build_context_query_fixtures }

  teardown do
    ContextQueryLog.where(run_step_id: @run_step&.id).destroy_all if @run_step
    @run_step&.destroy
    @run&.destroy
    @consumer&.destroy
    @producer&.destroy
    @schema&.destroy
  end

  def build_context_query_fixtures
    @schema = JsonSchema.create!(
      name: "integration_foundation",
      description: "Integration test schema",
      body: '{"type":"object","properties":{"title":{"type":"string"},"items":{"type":"array"}}}'
    )
    @workflow = workflows(:deploy)
    @workflow.steps.where(position: 800..).destroy_all

    @producer = @workflow.steps.create!(
      name: "Integration Producer", step_type: "prompt", body: "produce",
      position: 800, timeout: 30, max_retries: 0,
      config: { "produces" => ["foundation"], "json_schema_id" => @schema.id }
    )
    @consumer = @workflow.steps.create!(
      name: "Integration Consumer", step_type: "skill",
      skill: skills(:shared_skill),
      position: 801, timeout: 30, max_retries: 0,
      config: { "queries" => ["foundation"] }
    )

    @foundation_value = { "title" => "Hello World",
                          "items" => [{ "name" => "alpha" }, { "name" => "beta" }, { "name" => "gamma" }] }
    @run = @workflow.runs.create!(
      status: "running",
      context: { "foundation" => @foundation_value.to_json },
      input: {}
    )
    @run_step = @run.run_steps.create!(
      step: @consumer, status: "running", attempt: 1, position: 801,
      started_at: Time.current
    )
  end

  def executor_env
    executor = StepExecutor.new(@consumer, @run.context, "/tmp", run_step_id: @run_step.id)
    executor.send(:env_vars)
  end

  test "wrapper resolves on PATH set by the executor" do
    env = executor_env
    stdout, stderr, status = Open3.capture3(env, "seneschal-context", "foundation", ".title")
    assert status.success?, "exit=#{status.exitstatus}\nDB=#{env["SENESCHAL_DB_PATH"]}\nstdout=#{stdout.inspect}\nstderr=#{stderr.inspect}"
    assert_equal "\"Hello World\"\n", stdout
  end

  test "wrapper reads the live Rails run.context and pipes through jq" do
    env = executor_env

    title_out, _, title_status = Open3.capture3(env, WRAPPER, "foundation", ".title")
    assert title_status.success?
    assert_equal "\"Hello World\"\n", title_out

    count_out, _, count_status = Open3.capture3(env, WRAPPER, "foundation", ".items | length")
    assert count_status.success?
    assert_equal "3\n", count_out

    filter_out, _, filter_status = Open3.capture3(env, WRAPPER, "foundation", ".items[] | select(.name == \"beta\") | .name")
    assert filter_status.success?
    assert_equal "\"beta\"\n", filter_out
  end

  test "successful queries are logged against the right run_step" do
    env = executor_env

    Open3.capture3(env, WRAPPER, "foundation", ".title")
    Open3.capture3(env, WRAPPER, "foundation", "keys")

    logs = ContextQueryLog.where(run_step_id: @run_step.id).order(:created_at)
    assert_equal 2, logs.size
    assert_equal ["foundation", "foundation"], logs.pluck(:variable)
    assert_equal [".title", "keys"], logs.pluck(:expression)
    assert(logs.all? { |l| l.returned_bytes.positive? })
    assert(logs.all? { |l| l.error.nil? })
  end

  test "denied variables fail with non-zero exit and a logged error" do
    env = executor_env

    _, stderr, status = Open3.capture3(env, WRAPPER, "secrets", ".token")
    assert_equal 1, status.exitstatus
    assert_match(/not queryable/, stderr)

    log = ContextQueryLog.where(run_step_id: @run_step.id, variable: "secrets").last
    assert_not_nil log, "denied query should still be logged"
    assert_match(/not queryable/, log.error)
    assert_equal 0, log.returned_bytes
  end

  test "executor only enables query env vars when the step has matching queries" do
    bare = @workflow.steps.create!(
      name: "Plain Consumer", step_type: "skill",
      skill: skills(:shared_skill), position: 802,
      timeout: 30, max_retries: 0, config: {}
    )
    env = StepExecutor.new(bare, @run.context, "/tmp", run_step_id: @run_step.id).send(:env_vars)
    assert_not env.key?("SENESCHAL_QUERYABLE_VARS"),
               "non-querying step should not advertise queryable vars"
    bare.destroy
  end
end
