# shellcheck shell=bash
# common.sh — env defaults, logging, shared constants. Sourced by all lib/* and bin/ralph.

# --- env defaults (override by exporting before invoking `ralph`) ---
: "${RALPH_MAX_TURNS:=30}"           # per-phase pi invocation cap
: "${RALPH_CONTEXT_PCT:=0.5}"        # phase ends when ctx fraction >= this
: "${RALPH_MAX_ITERATIONS:=50}"      # global outer-loop cap
: "${RALPH_PI_BIN:=/opt/homebrew/bin/pi}"
: "${RALPH_RETRY_TRANSIENT:=1}"      # transient pi-error retries before counting
: "${RALPH_JOURNAL_EXCERPT_LEN:=250}"  # chars of assistant text per turn logged to JOURNAL.md; 0 = off

# --- two-model split: a high-reasoning planner + a fast code executor ---
# PLAN and VALIDATE run on RALPH_PLAN_MODEL (reasoning quality matters);
# IMPLEMENT runs on RALPH_EXEC_MODEL (code-gen throughput matters). Each model
# carries its own context window — MUST match the real window of the model pi
# runs, or the context cap is meaningless. Defaults assume LiteLLM aliases over
# Ollama: quality = qwen3.6:35b-mlx (ollama/quality),
# code = qwen2.5-coder:14b (ollama/code).
: "${RALPH_PLAN_MODEL:=quality}"          # PLAN + VALIDATE phases
: "${RALPH_EXEC_MODEL:=code}"             # IMPLEMENT phase
: "${RALPH_PLAN_CONTEXT_WINDOW:=131072}"  # context window of the plan model
: "${RALPH_EXEC_CONTEXT_WINDOW:=65536}"   # context window of the exec model
# RALPH_PROVIDER: unset by default; when set it applies to both models.

# --- signals (matched only in extracted assistant text) ---
RALPH_GOAL_DONE_SIGNAL='<goal-complete/>'
RALPH_PHASE_DONE_SIGNAL='<phase-done/>'

# --- phase exit codes (string, not shell rc) ---
# DONE TURN_CAP CTX_CAP  — all are non-fatal; the outer machine advances.

# --- logging: timestamped, to stderr so stdout stays clean ---
_ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }
log()  { printf '%s [ralph] %s\n'  "$(_ts)" "$*" >&2; }
warn() { printf '%s [ralph][warn] %s\n' "$(_ts)" "$*" >&2; }
die()  { printf '%s [ralph][fatal] %s\n' "$(_ts)" "$*" >&2; exit 1; }

# require a command on PATH
need() { command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"; }

# Build pi model args for a phase, one per line. PLAN and VALIDATE use the plan
# model; IMPLEMENT uses the exec model. RALPH_PROVIDER (optional) applies to
# both. Length-guarded: bash 3.2 + `set -u` errors on "${arr[@]}" for an empty
# array, so never expand it unguarded.
#   ralph_model_args <plan|implement|validate>
ralph_model_args() {
  local phase="$1" model args=()
  case "$phase" in
    implement) model="$RALPH_EXEC_MODEL" ;;
    *)         model="$RALPH_PLAN_MODEL" ;;
  esac
  [ -n "$model" ]              && args+=(--model "$model")
  [ -n "${RALPH_PROVIDER:-}" ] && args+=(--provider "$RALPH_PROVIDER")
  [ "${#args[@]}" -gt 0 ] && printf '%s\n' "${args[@]}"
  return 0
}

# Context window for a phase — MUST match the window of the model pi runs.
#   ralph_context_window <plan|implement|validate>
ralph_context_window() {
  case "$1" in
    implement) printf '%s\n' "$RALPH_EXEC_CONTEXT_WINDOW" ;;
    *)         printf '%s\n' "$RALPH_PLAN_CONTEXT_WINDOW" ;;
  esac
}
