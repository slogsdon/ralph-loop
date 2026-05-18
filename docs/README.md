# ralph-loop

A reusable, unattended **Ralph Wiggum loop** built on the [`pi`](https://pi.dev)
agent harness. Point it at any project and a goal; it drives
`PLAN → IMPLEMENT → VALIDATE` over shared filesystem state until the goal is
verifiably complete, with no human in the loop.

The overarching process is adapted from Shane's `Context/Development Workflow`
note (snapshot in `workflow/DEVELOPMENT_WORKFLOW.md`), injected into every
agent process as an appended system prompt.

## Why this exists

Tracks **OKR O3 KR2** — "ship and document 2+ agentic workflow automations,
each with a 60-day written evaluation." See `docs/EVALUATION.md`.

## How it works

- **Outer state machine** (`bin/ralph`): `PLAN → IMPLEMENT → VALIDATE`, looping.
  PLAN writes a discrete-task `BACKLOG.md`; IMPLEMENT works the first unchecked
  item; VALIDATE verifies with evidence and checks it off. Backlog drained but
  goal unmet → re-PLAN. Backlog drained **and** VALIDATE emits
  `<goal-complete/>` (re-verified by the orchestrator) → `COMPLETE`.
- **Inner per-phase resume-loop** (`lib/phase.sh`): each phase is its own
  isolated, ephemeral `pi` session. `pi` is called up to `RALPH_MAX_TURNS`
  times (resuming the phase session each turn). The phase ends on its
  `<phase-done/>` signal, the turn cap, or when context reaches
  `RALPH_CONTEXT_PCT` of `RALPH_CONTEXT_WINDOW` — whichever comes first.
  `pi` has no native turn/context limit; both caps are enforced here.
- **State between isolated processes** lives in `<target>/.ralph/` files, never
  in `pi` session memory — so hitting a cap is non-fatal: the next phase reads
  what the last one left behind. Forward progress is durable.

## Requirements

`pi` (v0.75+), `jq`, `awk`, `comm`, `shasum`, `sed`, `bash` 3.2+
(works on stock macOS `/bin/bash`).

## Quickstart

```bash
# 1. First run scaffolds <target>/.ralph/ and a GOAL.md template, then stops.
bin/ralph /path/to/target-project

# 2. Edit the objective + acceptance criteria.
$EDITOR /path/to/target-project/.ralph/GOAL.md

# 3. Pin the model so the context cap is meaningful (see note below), and run.
export RALPH_MODEL=claude-sonnet RALPH_PROVIDER=anthropic RALPH_CONTEXT_WINDOW=200000
bin/ralph /path/to/target-project
```

Re-running resumes from `STATE.json` (`phase`/`iteration`). Ctrl-C any time.

## Configuration

| Env var | Default | Meaning |
|---|---|---|
| `RALPH_MAX_TURNS` | `30` | per-phase `pi` invocation cap |
| `RALPH_CONTEXT_PCT` | `0.5` | phase ends when context fraction ≥ this |
| `RALPH_CONTEXT_WINDOW` | `200000` | model context window — **must match the pinned model** |
| `RALPH_MAX_ITERATIONS` | `50` | global outer-loop cap |
| `RALPH_MODEL` / `RALPH_PROVIDER` | unset | passed to `pi` as `--model`/`--provider` |
| `RALPH_PI_BIN` | `/opt/homebrew/bin/pi` | path to `pi` |
| `RALPH_RETRY_TRANSIENT` | `1` | transient `pi`-error retries before counting |

> **Pin the model.** `pi`'s effective model is ambient (resolved from its own
> config). If `RALPH_CONTEXT_WINDOW` does not match the real model's window,
> the 50% context cap is meaningless. For unattended runs, always set
> `RALPH_MODEL`, `RALPH_PROVIDER`, and a matching `RALPH_CONTEXT_WINDOW`.

## Safety model

| Control | Trips when | Terminal state | Exit |
|---|---|---|---|
| Kill switch | `<target>/.ralph/STOP` exists | `HALTED_STOP` | 0 |
| Global cap | iteration > `RALPH_MAX_ITERATIONS` | `HALTED_MAX_ITER` | 3 |
| Stuck | 3 identical consecutive `VALIDATION.md` | `HALTED_STUCK` | 4 |
| pi errors | 3 consecutive `pi` failures | `HALTED_PI_ERROR` | 5 |
| Turn cap | `RALPH_MAX_TURNS` turns in a phase | (non-fatal, advances) | — |
| Context cap | context ≥ `RALPH_CONTEXT_PCT` | (non-fatal, advances) | — |

Stop a run immediately: `touch <target>/.ralph/STOP`.

`HALTED_*` is sticky — `ralph` refuses to run until you resolve and reset:
remove `STOP`, raise `RALPH_MAX_ITERATIONS`, or delete
`<target>/.ralph/STATE.json` to restart clean. Every iteration and halt is
appended to `<target>/.ralph/JOURNAL.md`.

## State files (`<target>/.ralph/`)

| File | Written by | Read by |
|---|---|---|
| `GOAL.md` | you (once) | PLAN |
| `PLAN.md` | PLAN | IMPLEMENT, VALIDATE |
| `BACKLOG.md` | PLAN (add), VALIDATE (`- [x]`) | IMPLEMENT, orchestrator (drain test) |
| `VALIDATION.md` | VALIDATE (on fail) | IMPLEMENT, PLAN |
| `STATE.json` | orchestrator | orchestrator (resume source of truth) |
| `JOURNAL.md` | orchestrator | you / `EVALUATION.md` |
| `logs/<iter>-<phase>-<turn>.jsonl` | `pi` | debugging |

## Smoke test

```bash
rm -rf /tmp/ralph-smoke && mkdir /tmp/ralph-smoke && git -C /tmp/ralph-smoke init -q
bin/ralph /tmp/ralph-smoke    # scaffolds, then stops
cat > /tmp/ralph-smoke/.ralph/GOAL.md <<'EOF'
Create add.py exposing add(a, b) and a passing pytest test_add.py.
Acceptance: `pytest -q` exits 0 with at least one test for add(). Nothing else.
EOF
export RALPH_MODEL=... RALPH_PROVIDER=... RALPH_CONTEXT_WINDOW=...
bin/ralph /tmp/ralph-smoke

jq -r .phase /tmp/ralph-smoke/.ralph/STATE.json     # -> COMPLETE
( cd /tmp/ralph-smoke && pytest -q )                # -> green
```

Cap/halt checks (each independent):

```bash
RALPH_MAX_TURNS=2 bin/ralph /tmp/ralph-impossible        # phase exits TURN_CAP
RALPH_CONTEXT_WINDOW=2000 RALPH_CONTEXT_PCT=0.5 \
  bin/ralph /tmp/ralph-ctx                               # first turn -> CTX_CAP
touch /tmp/ralph-smoke/.ralph/STOP                       # -> HALTED_STOP, exit 0
RALPH_PI_BIN=/bin/false bin/ralph /tmp/ralph-smoke       # -> HALTED_PI_ERROR
```
