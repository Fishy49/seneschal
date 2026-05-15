module Runners
  # Common return value for every Runner. `structured_output` is populated
  # only when a runner that supports JSON-Schema-validated outputs (today
  # just ClaudeSDK) was given a schema and the agent produced a valid
  # response — the value is the parsed object, schema-conforming, ready to
  # land in the run context without further parsing or re-validation.
  Result = Data.define(:exit_code, :stdout, :stderr, :stream_events, :session_id, :structured_output) do
    # rubocop:disable Metrics/ParameterLists
    def initialize(exit_code:, stdout:, stderr:, stream_events: nil, session_id: nil, structured_output: nil)
      super
    end
    # rubocop:enable Metrics/ParameterLists

    def passed? = exit_code.zero?
  end
end
