# shellcheck shell=bash
# common.sh — env defaults, logging, shared constants. Sourced by all lib/* and bin/ralph.

# --- env defaults (override by exporting before invoking `ralph`) ---
: "${RALPH_MAX_TURNS:=30}"           # per-phase pi invocation cap
: "${RALPH_CONTEXT_PCT:=0.5}"        # phase ends when ctx fraction >= this
: "${RALPH_CONTEXT_WINDOW:=200000}"  # model context window — MUST match the pinned model
: "${RALPH_MAX_ITERATIONS:=50}"      # global outer-loop cap
: "${RALPH_PI_BIN:=/opt/homebrew/bin/pi}"
: "${RALPH_RETRY_TRANSIENT:=1}"      # transient pi-error retries before counting
# RALPH_MODEL / RALPH_PROVIDER: unset by default. Strongly recommended for
# unattended runs — pi's effective model is otherwise ambient and the context
# cap becomes meaningless if RALPH_CONTEXT_WINDOW does not match the real model.

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

# Build pi model args from optional env, one per line. Echoes nothing when
# neither is set. Length-guarded: bash 3.2 + `set -u` errors on "${arr[@]}"
# for an empty array, so never expand it unguarded.
ralph_model_args() {
  local args=()
  [ -n "${RALPH_MODEL:-}" ]    && args+=(--model "$RALPH_MODEL")
  [ -n "${RALPH_PROVIDER:-}" ] && args+=(--provider "$RALPH_PROVIDER")
  [ "${#args[@]}" -gt 0 ] && printf '%s\n' "${args[@]}"
  return 0
}
