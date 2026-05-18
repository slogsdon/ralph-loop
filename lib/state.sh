# shellcheck shell=bash
# state.sh — STATE.json (jq) + JOURNAL.md append. Requires $RALPH_TARGET set.

state_path()   { printf '%s/.ralph/STATE.json' "$RALPH_TARGET"; }
journal_path() { printf '%s/.ralph/JOURNAL.md' "$RALPH_TARGET"; }

# Append one timestamped, append-only audit line.
journal() {
  printf '%s  %s\n' "$(_ts)" "$*" >> "$(journal_path)"
}

# Create STATE.json on first run. No-op if it already exists.
state_init() {
  local sp; sp="$(state_path)"
  [ -f "$sp" ] && return 0
  jq -n --arg target "$RALPH_TARGET" \
        --arg ts "$(_ts)" \
        --argjson maxit "$RALPH_MAX_ITERATIONS" '
    { version: 1, target: $target, phase: "PLAN", iteration: 0,
      max_iterations: $maxit, started_at: $ts, updated_at: $ts,
      last_phase_exit: null, last_turns_used: 0, last_ctx_fraction: 0.0,
      consecutive_pi_errors: 0, recent_validation_hashes: [],
      goal_complete: false }' > "$sp"
  journal "INIT state created (max_iterations=$RALPH_MAX_ITERATIONS)"
}

# Read a single field via jq path expression, e.g. state_get '.phase'
state_get() { jq -r "$1" "$(state_path)"; }

# Apply a jq assignment filter; updated_at is always refreshed. Atomic write.
# e.g. state_update '.phase="IMPLEMENT" | .iteration=4'
state_update() {
  local sp tmp; sp="$(state_path)"; tmp="$(mktemp)"
  jq --arg ts "$(_ts)" "($1) | .updated_at=\$ts" "$sp" > "$tmp" && mv "$tmp" "$sp"
}

# Push a validation-output hash, keeping only the last 3.
state_push_vhash() {
  local sp tmp; sp="$(state_path)"; tmp="$(mktemp)"
  jq --arg h "$1" '.recent_validation_hashes =
       (.recent_validation_hashes + [$h] | .[-3:])' "$sp" > "$tmp" && mv "$tmp" "$sp"
}

# True when the last 3 validation hashes are identical and non-empty.
state_vhash_stuck() {
  local n
  n=$(jq -r '
    if (.recent_validation_hashes|length) < 3 then "no"
    elif (.recent_validation_hashes|unique|length)==1
         and (.recent_validation_hashes[0]|length)>0 then "yes"
    else "no" end' "$(state_path)")
  [ "$n" = "yes" ]
}
