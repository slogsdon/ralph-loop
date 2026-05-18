# shellcheck shell=bash
# safety.sh — runaway controls. Sourced after common.sh + state.sh.
# Any trip records terminal state, journals, and exits the process.

# Record a terminal halt and exit. STOP/COMPLETE are exit 0 (clean stop);
# other halts use a distinct non-zero code for scripting.
#   ralph_halt <PHASE_LABEL> <exit_code> <message>
ralph_halt() {
  local label="$1" code="$2" msg="$3"
  state_update ".phase=\"$label\""
  journal "HALT $label — $msg"
  log "halting: $label — $msg"
  exit "$code"
}

# Kill switch — checked before every iteration and every turn.
safety_check_stop() {
  if [ -f "$RALPH_TARGET/.ralph/STOP" ]; then
    ralph_halt "HALTED_STOP" 0 "STOP file present"
  fi
}

# Global outer-loop cap. Call with the iteration about to run.
safety_check_maxiter() {
  local iter="$1" maxit
  maxit="$(state_get '.max_iterations')"
  if [ "$iter" -gt "$maxit" ]; then
    ralph_halt "HALTED_MAX_ITER" 3 "iteration $iter exceeds max $maxit"
  fi
}

# pi exit-code accounting. Reset on success; halt after 3 consecutive failures.
safety_note_pi_ok() { state_update '.consecutive_pi_errors=0'; }
safety_note_pi_error() {
  local n
  state_update '.consecutive_pi_errors=(.consecutive_pi_errors+1)'
  n="$(state_get '.consecutive_pi_errors')"
  warn "pi error ($n consecutive)"
  if [ "$n" -ge 3 ]; then
    local tail_err=""
    [ -f "$RALPH_TARGET/.ralph/logs/pi.err" ] && \
      tail_err="$(tail -n 3 "$RALPH_TARGET/.ralph/logs/pi.err" | tr '\n' '|')"
    ralph_halt "HALTED_PI_ERROR" 5 "3 consecutive pi failures; stderr: ${tail_err}"
  fi
}

# Repeated-identical-VALIDATE-failure detector. Hash current VALIDATION.md,
# push to the rolling window, halt if the last 3 are identical.
safety_check_stuck() {
  local vf="$RALPH_TARGET/.ralph/VALIDATION.md" h
  [ -f "$vf" ] || return 0
  h="$(shasum "$vf" 2>/dev/null | awk '{print $1}')"
  [ -n "$h" ] || return 0
  state_push_vhash "$h"
  if state_vhash_stuck; then
    ralph_halt "HALTED_STUCK" 4 "3 identical consecutive VALIDATION.md failures"
  fi
}
