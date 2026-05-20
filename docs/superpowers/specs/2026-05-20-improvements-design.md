# ralph-loop improvements — design spec
**Date:** 2026-05-20

## Overview

Two targeted improvements motivated by real use:

1. **LLM excerpt journaling** — append a trimmed excerpt of each turn's assistant response to `JOURNAL.md` so failed/aborted turns are diagnosable without digging into raw `.jsonl` logs.
2. **Reset subcommand** — `ralph reset <target> [--keep-goal]` clears harness state so the same target directory can be pointed at a new goal without manual surgery.

---

## Feature 1: LLM Excerpt Journaling

### Motivation

`JOURNAL.md` currently logs only orchestrator-level events (iteration transitions, halts). When a run misbehaves — wrong decision, premature abort, bad plan — the only diagnostic is `tail -f logs/<iter>-<phase>-<turn>.jsonl`, which is verbose JSONL. A short inline excerpt makes `JOURNAL.md` self-sufficient for the most common "what happened?" question.

### Changes

**`lib/common.sh`** — new env var:
```bash
: "${RALPH_JOURNAL_EXCERPT_LEN:=250}"  # chars; 0 = off
```

**`lib/phase.sh`** — after `txt` is extracted (after the `pi_assistant_text` call), before signal checks:
```bash
local txt; txt="$(pi_assistant_text "$out")"

if [ "${RALPH_JOURNAL_EXCERPT_LEN:-250}" -gt 0 ]; then
  excerpt="$(printf '%s' "$txt" | head -c "${RALPH_JOURNAL_EXCERPT_LEN:-250}" | tr '\n' ' ')"
  journal "phase=$phase turn=$turn llm: ${excerpt}"
fi
```

Placement before signal checks is intentional: if the turn was aborted or the signal was missing, the excerpt still reveals what the model actually said.

### Journal output shape

```
2026-05-20T12:00:01Z  phase=plan turn=1 llm: I'll start by reading GOAL.md to understand the objective. The goal is to implement a CSV parser...
2026-05-20T12:00:45Z  iter=1 PLAN -> IMPLEMENT (exit=DONE, turns=1, ctx=0.0821)
```

### Configuration

| Env var | Default | Meaning |
|---|---|---|
| `RALPH_JOURNAL_EXCERPT_LEN` | `250` | Max chars of assistant text per turn; `0` disables |

### Constraints

- Uses `head -c` (POSIX; works on macOS/Linux).
- `tr '\n' ' '` collapses multiline output to a single journal line.
- No new dependencies.

---

## Feature 2: Reset Subcommand

### Motivation

After a run completes (or halts), reusing the same target directory for a new goal currently requires manually deleting or editing several `.ralph/` files. A dedicated subcommand makes the "new goal, same target" workflow explicit, safe, and auditable.

### Interface

```
ralph reset <target-project-dir> [--keep-goal]
```

- No flags → full reset including `GOAL.md` (user must fill it in before next run).
- `--keep-goal` → preserves existing `GOAL.md` (useful for retrying a goal after a bad run or manual state corruption).

### What reset does

| File / dir | Default reset | `--keep-goal` |
|---|---|---|
| `STATE.json` | deleted | deleted |
| `PLAN.md` | blanked | blanked |
| `BACKLOG.md` | reset to template | reset to template |
| `VALIDATION.md` | blanked | blanked |
| `sessions/` | wiped + recreated empty | wiped + recreated empty |
| `GOAL.md` | reset to template | **preserved** |
| `JOURNAL.md` | **preserved** | **preserved** |
| `logs/` | **preserved** | **preserved** |

`JOURNAL.md` and `logs/` are always preserved as audit history.

After reset, `STATE.json` is absent, so the next `ralph <target>` run calls `state_init` and starts from `phase=PLAN, iteration=0`. If `GOAL.md` was reset, the content guard (`grep -qvE '^\s*(<!--.*|$)'`) fires and stops the run with "edit GOAL.md, then re-run."

A `RESET` line is appended to `JOURNAL.md` so the audit trail is unbroken:
```
2026-05-20T12:05:00Z  RESET state cleared (keep_goal=0)
```

### Changes

**`bin/ralph`** — `usage()` updated:
```
Usage: ralph <target-project-dir>
       ralph reset <target-project-dir> [--keep-goal]
```

**`bin/ralph`** — arg check relaxed from `[ $# -eq 1 ]` to `[ $# -ge 1 ]`.

**`bin/ralph`** — new `do_reset()` function and `reset` case in arg dispatch, placed before the existing preflight block. `do_reset` uses `journal()` from `state.sh` (already sourced at top) and `log`/`die` from `common.sh`.

If `.ralph/` does not exist in the target, `do_reset` calls `die` with: `"no .ralph/ found in <target> — run ralph <target> first to initialise"`.

No new files. `do_reset` stays inline in `bin/ralph` — it's ~25 lines and shares no logic worth extracting.

---

## Files changed

| File | Change |
|---|---|
| `lib/common.sh` | Add `RALPH_JOURNAL_EXCERPT_LEN` default |
| `lib/phase.sh` | Excerpt journaling after `pi_assistant_text` call |
| `bin/ralph` | `usage()` update, arg check, `do_reset()`, `reset` dispatch case |
| `docs/README.md` | Document new env var + `reset` subcommand |
