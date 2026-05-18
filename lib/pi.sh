# shellcheck shell=bash
# pi.sh — pi invocation, per-phase session-UUID capture, JSON usage parsing.
#
# Reuses the proven UUID-capture technique from claude-code-config's agent-turn:
# snapshot-diff *.jsonl in --session-dir before/after the first call, then
# resume with --session <uuid>. Extended here with --mode json + usage parse.
#
# Globals expected: RALPH_PI_BIN, RALPH_HOME, RALPH_TARGET, RALPH_CONTEXT_WINDOW.
# Sets: RALPH_SESSION_UUID.

# Populate the global RALPH_PI_ARGS array for a phase: print flags + workflow
# doc + phase prompt as appended system prompts + optional model/provider.
_pi_build_args() {
  local phase="$1" line
  RALPH_PI_ARGS=(
    --print --mode json
    --append-system-prompt "$RALPH_HOME/workflow/DEVELOPMENT_WORKFLOW.md"
    --append-system-prompt "$RALPH_HOME/prompts/${phase}.md"
  )
  while IFS= read -r line; do
    [ -n "$line" ] && RALPH_PI_ARGS+=("$line")
  done < <(ralph_model_args)
}

# First turn of a phase: create the session, capture its UUID into
# RALPH_SESSION_UUID. pi's exit code is stashed in RALPH_PI_RC; the function
# itself always returns 0 so callers stay safe under `set -e`.
#   pi_run_first <phase> <session_dir> <out> <err> <prompt>
pi_run_first() {
  local phase="$1" sdir="$2" out="$3" err="$4" prompt="$5"
  local before after newf
  _pi_build_args "$phase"
  before="$(ls "$sdir"/*.jsonl 2>/dev/null | sort || true)"
  RALPH_PI_RC=0
  ( cd "$RALPH_TARGET" && "$RALPH_PI_BIN" "${RALPH_PI_ARGS[@]}" \
      --session-dir "$sdir" "$prompt" ) >"$out" 2>>"$err" || RALPH_PI_RC=$?
  after="$(ls "$sdir"/*.jsonl 2>/dev/null | sort || true)"
  newf="$(comm -13 <(echo "$before") <(echo "$after") | head -1 || true)"
  if [ -n "$newf" ]; then
    RALPH_SESSION_UUID="$(basename "$newf" | sed 's/^[^_]*_//; s/\.jsonl$//')"
  else
    RALPH_SESSION_UUID=""
  fi
  return 0
}

# Subsequent turns: resume the captured session. pi's exit code is stashed in
# RALPH_PI_RC; the function always returns 0 (set -e safe).
#   pi_run_resume <phase> <uuid> <session_dir> <out> <err> <prompt>
pi_run_resume() {
  local phase="$1" uuid="$2" sdir="$3" out="$4" err="$5" prompt="$6"
  _pi_build_args "$phase"
  RALPH_PI_RC=0
  ( cd "$RALPH_TARGET" && "$RALPH_PI_BIN" "${RALPH_PI_ARGS[@]}" \
      --session "$uuid" --session-dir "$sdir" "$prompt" ) >"$out" 2>>"$err" || RALPH_PI_RC=$?
  return 0
}

# Cumulative context tokens for the turn = last non-zero usage.input on a
# terminal line. Streaming message_update lines are zero-filled and ignored.
pi_ctx_input() {
  grep -E '"type":"(turn_end|agent_end|message_end)"' "$1" 2>/dev/null \
    | jq -r 'select(.message.usage.input>0) | .message.usage.input' 2>/dev/null \
    | tail -1
}

# Context fraction for this turn. Primary: parsed usage. Fallback: transcript
# char estimate (chars/4) when no usable usage line. Echoes "<fraction> <mode>".
pi_ctx_fraction() {
  local out="$1" sdir="$2" input mode="usage" chars
  input="$(pi_ctx_input "$out")"
  if [ -z "$input" ]; then
    mode="estimate"
    chars="$(jq -rs '[.[] | (.message.content[]?.text // empty)] | join("") | length' \
              "$sdir"/*.jsonl 2>/dev/null || echo 0)"
    input=$(( ${chars:-0} / 4 ))
  fi
  awk -v i="${input:-0}" -v w="$RALPH_CONTEXT_WINDOW" -v m="$mode" \
      'BEGIN { f = (w>0) ? i/w : 1; printf "%.4f %s\n", f, m }'
}

# Assistant text from the agent_end record only — avoids false-positive signal
# matches on pi's echoed prompt / thinking blocks.
pi_assistant_text() {
  jq -r 'select(.type=="agent_end").messages[]?
         | select(.role=="assistant").content[]? | (.text // empty)' \
     "$1" 2>/dev/null
}
