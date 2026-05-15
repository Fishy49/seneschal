module Runners
  Result = Data.define(:exit_code, :stdout, :stderr, :stream_events, :session_id) do
    def initialize(exit_code:, stdout:, stderr:, stream_events: nil, session_id: nil)
      super
    end

    def passed? = exit_code.zero?
  end
end
