"""Seneschal SDK runner.

Reads a JSON config from stdin describing a Claude Agent SDK invocation,
runs it, and streams NDJSON events to stdout in the same shape as the
`claude` CLI's `--output-format stream-json` so the existing Ruby-side
parser (`Runners::ClaudeCLI`'s consumer) works unchanged.

Wire contract — stdin (single JSON object):

    {
      "prompt": "...",
      "cwd": "/path",
      "model": "claude-opus-4-7" | null,
      "max_turns": 5 | null,
      "allowed_tools": ["Bash", "Read"] | null,
      "permission_mode": "default" | "acceptEdits" | "bypassPermissions" | "plan" | "dontAsk",
      "dangerously_skip_permissions": false,
      "add_dirs": ["/path1"],
      "resume_session_id": null,
      "resume_message": null,
      "system_prompt": null,
      "json_schema": {"type": "object", "properties": {...}} | null
    }

When ``json_schema`` is non-null the sidecar wires the SDK's
``output_format={"type": "json_schema", "schema": ...}``, and the result
event's ``structured_output`` will carry the parsed, schema-validated
object.

Wire contract — stdout (one JSON event per line):

    {"type": "system", "session_id": "...", "model": "..."}
    {"type": "assistant", "message": {"content": [{"type": "text", "text": "..."}]}, "session_id": "..."}
    {"type": "result", "result": "...", "session_id": "...",
     "total_cost_usd": 0.01, "num_turns": 3, "duration_ms": 5000}

On error: emits one final {"type": "error", "message": "..."} event to
stdout and exits with status 1.

Exit codes:
    0 — success (a `result` event was emitted)
    1 — any error before/during the SDK call
"""

from __future__ import annotations

import asyncio
import json
import sys
import traceback
from typing import Any


def _json_safe_default(obj: Any) -> Any:
    """Last-ditch JSON serializer for SDK dataclass / pydantic-like
    instances we forgot to unpack — fall back to a dict of public attrs,
    then to str(), so a single weird field never kills the event stream."""
    if hasattr(obj, "__dict__"):
        return {k: v for k, v in vars(obj).items() if not k.startswith("_")}
    return str(obj)


def emit(event: dict[str, Any]) -> None:
    """Write a single NDJSON event to stdout, flushing immediately so the
    Ruby parent reads it without buffering delay."""
    sys.stdout.write(json.dumps(event, default=_json_safe_default) + "\n")
    sys.stdout.flush()


def serialize_content_blocks(blocks: Any) -> list[dict[str, Any]]:
    """Translate a list of SDK content blocks (TextBlock, ToolUseBlock,
    ToolResultBlock, etc.) into plain JSON-serializable dicts in the same
    shape the `claude` CLI emits over `--output-format stream-json`."""
    out: list[dict[str, Any]] = []
    for block in blocks or []:
        block_type = type(block).__name__
        if block_type == "TextBlock":
            out.append({"type": "text", "text": getattr(block, "text", "")})
        elif block_type == "ToolUseBlock":
            out.append({
                "type": "tool_use",
                "id": getattr(block, "id", None),
                "name": getattr(block, "name", None),
                "input": getattr(block, "input", None) or {},
            })
        elif block_type == "ToolResultBlock":
            out.append({
                "type": "tool_result",
                "tool_use_id": getattr(block, "tool_use_id", None),
                "content": getattr(block, "content", None),
                "is_error": getattr(block, "is_error", False),
            })
        elif block_type == "ThinkingBlock":
            out.append({"type": "thinking", "thinking": getattr(block, "thinking", "")})
    return out


def serialize_message(msg: Any, session_id: str | None) -> dict[str, Any] | None:
    """Translate one SDK message object into a CLI-shaped NDJSON event.

    Returns None for message types we don't care to surface (keeps the
    stream clean). Defensive about attribute access — the SDK's types
    have evolved across versions, so we duck-type and fall back to repr()
    rather than crashing on an unknown shape.
    """
    msg_type = type(msg).__name__

    if msg_type == "SystemMessage":
        data = getattr(msg, "data", None) or {}
        return {
            "type": "system",
            "session_id": session_id or data.get("session_id"),
            "model": data.get("model") or getattr(msg, "model", None),
        }

    if msg_type == "AssistantMessage":
        return {
            "type": "assistant",
            "message": {"content": serialize_content_blocks(getattr(msg, "content", None))},
            "session_id": session_id,
        }

    if msg_type == "UserMessage":
        # Tool results from the host appear as UserMessages. Their `content`
        # is a list of SDK block objects (typically ToolResultBlock) — has
        # to be unpacked the same way as AssistantMessage or json.dumps
        # blows up trying to serialize the raw dataclass.
        return {
            "type": "user",
            "message": {"content": serialize_content_blocks(getattr(msg, "content", None))},
            "session_id": session_id,
        }

    if msg_type == "ResultMessage":
        # NOTE: `usage` is a passthrough dict from the Anthropic API — same
        # keys (input_tokens, output_tokens, cache_creation_input_tokens,
        # cache_read_input_tokens) as the CLI's `--output-format stream-json`
        # emits, so RunStep#usage_stats keeps working unchanged.
        return {
            "type": "result",
            "subtype": getattr(msg, "subtype", None),
            "is_error": getattr(msg, "is_error", False),
            "result": getattr(msg, "result", "") or "",
            "session_id": session_id or getattr(msg, "session_id", None),
            "total_cost_usd": getattr(msg, "total_cost_usd", None),
            "num_turns": getattr(msg, "num_turns", None),
            "duration_ms": getattr(msg, "duration_ms", None),
            "duration_api_ms": getattr(msg, "duration_api_ms", None),
            "usage": getattr(msg, "usage", None) or {},
            "model_usage": getattr(msg, "model_usage", None),
            "permission_denials": getattr(msg, "permission_denials", None),
            "stop_reason": getattr(msg, "stop_reason", None),
            # Populated when the caller passed `json_schema` in the wire
            # config (which the sidecar maps to ClaudeAgentOptions.output_format).
            # The Ruby StepExecutor uses this directly as the step's
            # produced value and skips its prompt-engineered retry loop
            # since the SDK already enforced the schema upstream.
            "structured_output": getattr(msg, "structured_output", None),
        }

    return None  # unknown message type — drop quietly


def extract_session_id(msg: Any) -> str | None:
    """Pull the session id out of any SDK message that carries one."""
    sid = getattr(msg, "session_id", None)
    if sid:
        return sid
    data = getattr(msg, "data", None)
    if isinstance(data, dict):
        return data.get("session_id")
    return None


def build_options(config: dict[str, Any]) -> Any:
    """Translate the Ruby-side kwargs hash into ClaudeAgentOptions.

    Only set fields the caller actually provided — pass `None` for
    unspecified ones so the SDK uses its own defaults.
    """
    from claude_agent_sdk import ClaudeAgentOptions

    # The SDK's permission_mode literal includes 'dontAsk' natively as of
    # 0.2.x, so we forward whatever the Ruby caller gave us. The
    # `dangerously_skip_permissions` shortcut still maps to the SDK's
    # explicit bypass enum.
    permission_mode = (
        "bypassPermissions"
        if config.get("dangerously_skip_permissions")
        else (config.get("permission_mode") or "default")
    )

    kwargs: dict[str, Any] = {
        "permission_mode": permission_mode,
    }

    if config.get("model"):
        kwargs["model"] = config["model"]
    if config.get("max_turns") is not None:
        kwargs["max_turns"] = int(config["max_turns"])
    if config.get("cwd"):
        kwargs["cwd"] = config["cwd"]
    if config.get("system_prompt"):
        kwargs["system_prompt"] = config["system_prompt"]

    allowed = config.get("allowed_tools")
    if isinstance(allowed, str):
        allowed = [t.strip() for t in allowed.split(",") if t.strip()]
    if allowed:
        kwargs["allowed_tools"] = allowed

    add_dirs = config.get("add_dirs") or []
    if add_dirs:
        kwargs["add_dirs"] = list(add_dirs)

    if config.get("resume_session_id"):
        kwargs["resume"] = config["resume_session_id"]

    # Schema-validated structured outputs. The SDK takes the schema via
    # `output_format={"type": "json_schema", "schema": <schema>}` and
    # surfaces the parsed object back on ResultMessage.structured_output.
    schema = config.get("json_schema")
    if isinstance(schema, dict) and schema:
        kwargs["output_format"] = {"type": "json_schema", "schema": schema}

    return ClaudeAgentOptions(**kwargs)


def resolve_prompt(config: dict[str, Any]) -> str:
    """The prompt sent to the agent. On a resume, the SDK's `resume`
    option points at the prior session and the prompt is the new turn —
    use the resume_message if given, else a sensible default."""
    if config.get("resume_session_id"):
        return (
            config.get("resume_message")
            or "Your previous session was interrupted. Continue and complete the task."
        )
    return config.get("prompt") or ""


async def run(config: dict[str, Any]) -> int:
    try:
        from claude_agent_sdk import query
    except ImportError as exc:
        emit({
            "type": "error",
            "message": (
                f"claude-agent-sdk is not installed in this Python environment "
                f"({exc}). Run bin/setup_sdk_runner."
            ),
        })
        return 1

    options = build_options(config)
    prompt = resolve_prompt(config)

    session_id: str | None = None
    saw_result = False

    try:
        async for message in query(prompt=prompt, options=options):
            session_id = extract_session_id(message) or session_id
            event = serialize_message(message, session_id)
            if event is None:
                continue
            emit(event)
            if event.get("type") == "result":
                saw_result = True
    except Exception as exc:  # noqa: BLE001 — top-level boundary
        emit({
            "type": "error",
            "message": f"{type(exc).__name__}: {exc}",
            "traceback": traceback.format_exc(),
        })
        return 1

    if not saw_result:
        emit({
            "type": "error",
            "message": "SDK query completed without emitting a ResultMessage.",
        })
        return 1

    return 0


def cli() -> None:
    raw = sys.stdin.read()
    try:
        config = json.loads(raw)
    except json.JSONDecodeError as exc:
        emit({"type": "error", "message": f"invalid JSON config on stdin: {exc}"})
        sys.exit(1)

    sys.exit(asyncio.run(run(config)))


if __name__ == "__main__":
    cli()
