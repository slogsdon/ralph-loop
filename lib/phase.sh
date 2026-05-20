# shellcheck shell=bash
# phase.sh — inner per-phase resume-loop with dual turn + context cap.
#
# Each phase gets its own ephemeral pi session (wiped on entry). Cross-phase
# state flows through .ralph/*.md files, never pi session memory — so TURN_CAP
# and CTX_CAP are non-fatal: the next phase just reads the files left behind.
#
# Sets globals: RALPH_PHASE_EXIT (DONE|TURN_CAP|CTX_CAP), RALPH_SAW_GOAL_DONE.

_journal_llm_excerpt() {
  local phase="$1" turn="$2" txt="$3"
  [ "${RALPH_JOURNAL_EXCERPT_LEN:-250}" -gt 0 ] || return 0
  [ -n "$txt" ] || return 0
  local excerpt
  excerpt="$(printf '%s' "$txt" | head -c "${RALPH_JOURNAL_EXCERPT_LEN:-250}" | tr '\n' ' ')"
  journal "phase=$phase turn=$turn llm: ${excerpt}"
}

# float ">=" via awk; returns 0 (true) when a >= b.
_fge() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a>=b)}'; }

# Per-turn driver message. The role/instructions live in prompts/<phase>.md
# (injected as an appended system prompt); this just points pi at the work.
_phase_prompt() {
  local phase="$1" turn="$2" PHASE_UC
  PHASE_UC="$(printf '%s' "$phase" | tr '[:lower:]' '[:upper:]')"
  if [ "$turn" -eq 1 ]; then
    cat <<EOF
Begin the ${PHASE_UC} phase now. The working directory is the target project.
Read .ralph/GOAL.md, .ralph/PLAN.md, .ralph/BACKLOG.md and .ralph/VALIDATION.md
as relevant to your role. Follow your system instructions exactly.
Print the line ${RALPH_PHASE_DONE_SIGNAL} on its own line when this phase's
objective is fully met. If the entire goal is verified complete AND
.ralph/BACKLOG.md has no unchecked items, print ${RALPH_GOAL_DONE_SIGNAL}.
EOF
  else
    cat <<EOF
Continue. When this phase's objective is fully met, print ${RALPH_PHASE_DONE_SIGNAL}
on its own line and stop. If the entire goal is verified complete and
.ralph/BACKLOG.md has no unchecked items, print ${RALPH_GOAL_DONE_SIGNAL}.
EOF
  fi
}

# run_phase <plan|implement|validate>
run_phase() {
  local phase="$1"
  local sdir="$RALPH_TARGET/.ralph/sessions/$phase"
  local logdir="$RALPH_TARGET/.ralph/logs"
  local err="$logdir/pi.err"
  local iter turn=0 uuid="" prompt out rc frac fmode

  iter="$(state_get '.iteration')"
  rm -rf "$sdir"; mkdir -p "$sdir" "$logdir"
  RALPH_PHASE_EXIT=""; RALPH_SAW_GOAL_DONE=0

  while [ "$turn" -lt "$RALPH_MAX_TURNS" ]; do
    safety_check_stop
    turn=$((turn + 1))
    prompt="$(_phase_prompt "$phase" "$turn")"
    out="$logdir/${iter}-${phase}-${turn}.jsonl"
    log "phase=$phase iter=$iter turn=$turn/$RALPH_MAX_TURNS"

    if [ -z "$uuid" ]; then
      pi_run_first  "$phase" "$sdir" "$out" "$err" "$prompt"; rc=$RALPH_PI_RC
      uuid="$RALPH_SESSION_UUID"
    else
      pi_run_resume "$phase" "$uuid" "$sdir" "$out" "$err" "$prompt"; rc=$RALPH_PI_RC
    fi

    # transient retry, then count toward the pi-error halt threshold
    if [ "$rc" -ne 0 ]; then
      local r=0
      while [ "$r" -lt "$RALPH_RETRY_TRANSIENT" ] && [ "$rc" -ne 0 ]; do
        r=$((r + 1)); warn "pi rc=$rc — transient retry $r"
        if [ -z "$uuid" ]; then
          pi_run_first  "$phase" "$sdir" "$out" "$err" "$prompt"; rc=$RALPH_PI_RC
          uuid="$RALPH_SESSION_UUID"
        else
          pi_run_resume "$phase" "$uuid" "$sdir" "$out" "$err" "$prompt"; rc=$RALPH_PI_RC
        fi
      done
    fi
    if [ "$rc" -ne 0 ]; then
      safety_note_pi_error      # may halt at 3 consecutive
      continue                  # skip parsing a failed turn
    fi
    safety_note_pi_ok

    local txt; txt="$(pi_assistant_text "$out")"
    _journal_llm_excerpt "$phase" "$turn" "$txt"

    if printf '%s' "$txt" | grep -qF "$RALPH_GOAL_DONE_SIGNAL"; then
      RALPH_SAW_GOAL_DONE=1; RALPH_PHASE_EXIT="DONE"
      state_update ".last_turns_used=$turn | .last_phase_exit=\"DONE\""
      log "phase=$phase saw goal-complete signal"
      return 0
    fi
    if printf '%s' "$txt" | grep -qF "$RALPH_PHASE_DONE_SIGNAL"; then
      RALPH_PHASE_EXIT="DONE"
      state_update ".last_turns_used=$turn | .last_phase_exit=\"DONE\""
      return 0
    fi

    read -r frac fmode < <(pi_ctx_fraction "$out" "$sdir")
    state_update ".last_ctx_fraction=${frac:-0}"
    if _fge "${frac:-0}" "$RALPH_CONTEXT_PCT"; then
      RALPH_PHASE_EXIT="CTX_CAP"
      state_update ".last_turns_used=$turn | .last_phase_exit=\"CTX_CAP\""
      log "phase=$phase context cap: frac=$frac ($fmode) >= $RALPH_CONTEXT_PCT"
      return 0
    fi
  done

  RALPH_PHASE_EXIT="TURN_CAP"
  state_update ".last_turns_used=$turn | .last_phase_exit=\"TURN_CAP\""
  log "phase=$phase turn cap reached ($RALPH_MAX_TURNS)"
  return 0
}
