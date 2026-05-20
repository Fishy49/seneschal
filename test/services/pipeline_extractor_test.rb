require "test_helper"

class PipelineExtractorTest < ActiveSupport::TestCase
  setup do
    @step = steps(:skill_step)
    @step.update!(config: @step.config.merge("produces" => ["foundation"]))
  end

  # Regression: run #50 failed because splice_structured_output JSON-encoded the
  # SDK's parsed payload into a ```output fence, and PipelineExtractor's
  # non-greedy /```output\s*\n(.*?)```/m regex closed on the FIRST triple-backtick
  # it saw. A schema-produced project_layout value displayed a directory tree as
  # a Markdown code block — that internal ``` truncated foundation to invalid
  # JSON, JsonPathResolver rescued the parse error, and every foundation.* consume
  # downstream resolved to nil. Routing structured_output straight through
  # produces.first avoids the round-trip entirely.
  test "prefers result.structured_output over text extraction when present" do
    payload = {
      "title" => "Driver Out!",
      "project_layout" => "```\ndriver-out/\n  src/\n  assets/\n```",
      "schema_version" => 1
    }

    result = Runners::Result.new(
      exit_code: 0,
      stdout: "Narrative text from the model.",
      stderr: "",
      structured_output: payload
    )

    extracted = PipelineExtractor.new(@step, result).extract

    assert_equal payload, extracted["foundation"]
    assert_equal payload["project_layout"], extracted["foundation"]["project_layout"],
                 "the triple-backtick inside project_layout must survive extraction"
  end

  test "falls back to text-based output block extraction when structured_output is nil" do
    stdout = <<~OUT
      Narrative.

      ```output
      foundation: {"title":"Plain"}
      ```
    OUT

    result = Runners::Result.new(exit_code: 0, stdout: stdout, stderr: "", structured_output: nil)
    extracted = PipelineExtractor.new(@step, result).extract

    assert_equal '{"title":"Plain"}', extracted["foundation"]
  end

  test "still accepts a raw stdout string for backward compatibility" do
    stdout = "::set-output foo=bar\n"
    step = steps(:command_step)
    step.update!(config: step.config.merge("produces" => ["foo"]))

    extracted = PipelineExtractor.new(step, stdout).extract
    assert_equal "bar", extracted["foo"]
  end

  test "skips structured_output routing when produces is empty" do
    @step.update!(config: @step.config.merge("produces" => []))
    result = Runners::Result.new(exit_code: 0, stdout: "", stderr: "", structured_output: { "x" => 1 })

    assert_empty PipelineExtractor.new(@step, result).extract
  end
end
