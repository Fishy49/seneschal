# Seneschal SDK Runner

A small Python sidecar that lets the Seneschal Rails app invoke the
[Claude Agent SDK](https://github.com/anthropics/claude-agent-sdk-python) over
a subprocess + NDJSON wire protocol.

Lives here because Seneschal is Ruby and the SDK is Python-only. Rails spawns
this script with a JSON config on stdin; the script streams events back as
NDJSON (same shape as the `claude` CLI's `--output-format stream-json`) so the
existing Ruby parser keeps working unchanged.

## Install

From the repo root:

```bash
bin/setup_sdk_runner
```

That script does the right thing whether you have `uv` (preferred) or just
`python3 + pip`. Either way, it leaves a working venv at
`lib/sdk_runner/.venv/` and the `Runners::ClaudeSDK` runner picks it up
automatically.

If you'd rather drive it manually:

```bash
# Option A — uv (faster, no global state)
uv venv lib/sdk_runner/.venv
uv pip install --python lib/sdk_runner/.venv/bin/python -e lib/sdk_runner

# Option B — stock python + pip
python3 -m venv lib/sdk_runner/.venv
lib/sdk_runner/.venv/bin/pip install -e lib/sdk_runner
```

## Use

By default, Seneschal still routes every Skill/Prompt step through
`Runners::ClaudeCLI` (the existing `claude -p` shell-out). To opt a step
into the SDK runner:

```ruby
step.update!(config: step.config.merge("runner" => "claude_sdk"))
```

Or flip the global default:

```ruby
Setting["default_runner"] = "claude_sdk"
```

## Wire format

Stdin: a single JSON object:

```json
{
  "prompt": "Implement the feature described in $TASK_BODY",
  "cwd": "/Users/rick/code/seneschal/tmp/worktrees/42",
  "model": "claude-opus-4-7",
  "max_turns": 5,
  "allowed_tools": ["Bash", "Read", "Edit"],
  "permission_mode": "default",
  "dangerously_skip_permissions": false,
  "add_dirs": ["/path/to/peer/project"],
  "resume_session_id": null,
  "resume_message": null,
  "system_prompt": null
}
```

Stdout: one JSON event per line (NDJSON). The shape mirrors the `claude` CLI's
`--output-format stream-json` so consumers don't have to special-case:

```
{"type":"system","session_id":"sess_abc","model":"claude-opus-4-7"}
{"type":"assistant","message":{"content":[{"type":"text","text":"Reading the file..."}]},"session_id":"sess_abc"}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"tu_1","name":"Read","input":{"file_path":"foo.rb"}}]},"session_id":"sess_abc"}
{"type":"result","subtype":"success","is_error":false,"result":"Done.","session_id":"sess_abc","total_cost_usd":0.0123,"num_turns":3,"duration_ms":4521}
```

On error: emits a final `{"type":"error","message":"..."}` event and exits 1.

## Why a subprocess and not a long-lived daemon?

- Per-Step process isolation: a crash in one step's agent doesn't affect any
  other run, and there's no shared in-memory state to leak.
- Matches the existing `claude` CLI invocation pattern exactly — the only
  thing that changes is the binary, not the lifecycle.
- Python interpreter startup (~150ms) + SDK import (~300ms) is in the noise
  vs typical step duration (seconds to minutes). Not worth the daemon
  lifecycle complexity for the latency win.

If a future use case wants persistent state (e.g. a hot model cache), a
long-lived runner is a clean follow-up — just register a new
`Runners::ClaudeSdkDaemon` alongside this one.
