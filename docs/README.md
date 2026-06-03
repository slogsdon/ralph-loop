# ralph-loop

A reusable, unattended loop built on the [`pi`](https://pi.dev) agent harness.
Point it at any project and a goal; it drives `PLAN → IMPLEMENT → VALIDATE`
over shared filesystem state until the goal is verifiably complete, with no
human in the loop.

The development workflow is injected into every agent process as an appended
system prompt (snapshot in `workflow/DEVELOPMENT_WORKFLOW.md`).

## Why this exists

Most agentic coding loops break in a way that demands human attention before
they can continue. Turn 8 stalls, the model loses the thread, and nobody's
there to step in.

This harness is built around that failure mode. Each phase runs in its own
isolated `pi` session. State flows through files, not agent memory, so hitting
a cap (turns or context) doesn't lose progress. The next phase just reads what
the last one left behind. A STOP file halts cleanly at the next boundary.
Three identical VALIDATE results in a row trip the stuck detector. The loop
either reaches COMPLETE or lands in a named HALTED_* state with a reason you
can act on.

The PLAN/IMPLEMENT/VALIDATE structure means unvalidated work can't get through.
Validation failure is the input to the next cycle, not a crash.

See `docs/EVALUATION.md` for how the first 60 days are being tracked.

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
  `RALPH_CONTEXT_PCT` of the phase's context window — whichever comes first.
  `pi` has no native turn/context limit; both caps are enforced here.
- **State between isolated processes** lives in `<target>/.ralph/` files, never
  in `pi` session memory — so hitting a cap is non-fatal: the next phase reads
  what the last one left behind. Forward progress is durable.

## Requirements

`pi` (v0.75+), `git`, `jq`, `awk`, `comm`, `shasum`, `sed`, `bash` 3.2+
(works on stock macOS `/bin/bash`). The target project should be a **git
repo** — the workflow does test-first development and the harness adds
`.ralph/` to the target's `.gitignore`. No language/test tooling is required
by the harness itself; whatever your `GOAL.md` acceptance check runs is up to
you (the examples below need only `python3`).

By default the harness uses whatever model `pi` is already configured for —
typically a **local model** (e.g. LM Studio / Ollama). No API keys or model
flags are needed for the default local path.

## Install (optional)

Run `ralph` from anywhere by symlinking it onto your PATH (the script
resolves through symlinks to find its own files):

```bash
ln -sfn "$PWD/bin/ralph" /opt/homebrew/bin/ralph   # user-writable, on PATH
# or, for /usr/local/bin (root-owned, needs sudo):
sudo ln -sfn "$PWD/bin/ralph" /usr/local/bin/ralph
```

Otherwise just invoke `bin/ralph` from the repo, or by absolute path.

## Quickstart

Default path — local model, no API keys, no model flags:

```bash
# 0. Target should be a git repo.
git -C /path/to/target-project rev-parse 2>/dev/null || git -C /path/to/target-project init

# 1. First run scaffolds <target>/.ralph/ and a GOAL.md template, then stops.
bin/ralph /path/to/target-project          # or an absolute path from anywhere

# 2. Edit the objective + acceptance criteria.
$EDITOR /path/to/target-project/.ralph/GOAL.md

# 3. The two-model defaults (planner=quality, executor=code) suit a standard
#    local LiteLLM/Ollama setup. Override the windows if your models differ.
export RALPH_PLAN_CONTEXT_WINDOW=131072    # PLAN + VALIDATE model window
export RALPH_EXEC_CONTEXT_WINDOW=65536     # IMPLEMENT model window
bin/ralph /path/to/target-project
```

`bin/ralph -h` prints usage. Re-running resumes from `STATE.json`
(`phase`/`iteration`); Ctrl-C any time and re-run to continue.

Optional — swap the planner/executor models or pin a provider for both:

```bash
export RALPH_PLAN_MODEL=quality RALPH_EXEC_MODEL=code RALPH_PROVIDER=ollama
bin/ralph /path/to/target-project
```

## Monitoring a run

A run is unattended and can take a while (local models are slow). Watch
progress without interrupting it:

```bash
tail -f /path/to/target-project/.ralph/JOURNAL.md   # one line per iteration / halt
```

Done = process exit `0` and `jq -r .phase .ralph/STATE.json` → `COMPLETE`.
Any `HALTED_*` phase is a stop that needs attention (see Safety model).
Per-turn raw `pi` output is under `.ralph/logs/<iter>-<phase>-<turn>.jsonl`
for debugging.

## Resetting for a new goal

After a run completes or halts, reuse the same target directory for a new goal:

```bash
ralph reset /path/to/target-project             # wipes state + resets GOAL.md to template
ralph reset /path/to/target-project --keep-goal # wipes state, keeps existing GOAL.md
```

`JOURNAL.md` and `logs/` are always preserved as audit history. `reset` requires
`.ralph/` to exist (initialise with a regular `ralph` run first if needed).
After a full reset, fill in `.ralph/GOAL.md` then re-run `ralph <target>` to start fresh.

## Configuration

| Env var | Default | Meaning |
|---|---|---|
| `RALPH_MAX_TURNS` | `30` | per-phase `pi` invocation cap |
| `RALPH_CONTEXT_PCT` | `0.5` | phase ends when context fraction ≥ this |
| `RALPH_PLAN_MODEL` / `RALPH_EXEC_MODEL` | `quality` / `code` | planner (PLAN+VALIDATE) and executor (IMPLEMENT) models — LiteLLM aliases over Ollama (`quality` = qwen3.6:35b-mlx, `code` = qwen2.5-coder:14b) |
| `RALPH_PLAN_CONTEXT_WINDOW` / `RALPH_EXEC_CONTEXT_WINDOW` | `131072` / `65536` | context window of each model `pi` actually uses — set to each model's real window |
| `RALPH_MAX_ITERATIONS` | `50` | global outer-loop cap |
| `RALPH_PROVIDER` | unset | unset = use `pi`'s ambient provider; set to pin a provider for both models |
| `RALPH_PI_BIN` | `/opt/homebrew/bin/pi` | path to `pi` |
| `RALPH_RETRY_TRANSIENT` | `1` | transient `pi`-error retries before counting |
| `RALPH_JOURNAL_EXCERPT_LEN` | `250` | chars of assistant text appended to `JOURNAL.md` per turn; `0` disables |

> **Set each context window to its model's real window.** The context cap is
> only meaningful if `RALPH_PLAN_CONTEXT_WINDOW` / `RALPH_EXEC_CONTEXT_WINDOW`
> match the windows of the models `pi` actually runs. A window larger than the
> real one effectively disables the cap for that phase (it never trips), so set
> both to match your planner and executor models. Override `RALPH_PLAN_MODEL` /
> `RALPH_EXEC_MODEL` (and optionally `RALPH_PROVIDER`) to swap either model.

> **Model vars take the name `pi` resolves, not the raw backend tag.**
> `RALPH_PLAN_MODEL` / `RALPH_EXEC_MODEL` are forwarded verbatim to `pi
> --model`. Behind a LiteLLM proxy that is the **alias** (`quality`, `code`,
> `review`, `write`, …) — *not* the Ollama tag like `qwen2.5-coder:14b`. An
> unknown name fails every turn with `Model "…" not found` and the run halts
> `HALTED_PI_ERROR` after the consecutive-pi-error threshold. List valid names
> with `pi --list-models`. The **executor must also be tool-capable**: a model
> that prints tool calls as plain text rather than structured calls never
> actually edits files, so the IMPLEMENT phase runs to its turn cap doing
> nothing. Verify with a one-shot tool-calling request before relying on it.

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

Dependency-light goal (only `python3`), default local model:

```bash
rm -rf /tmp/ralph-smoke && mkdir /tmp/ralph-smoke && git -C /tmp/ralph-smoke init -q
bin/ralph /tmp/ralph-smoke    # scaffolds, then stops
cat > /tmp/ralph-smoke/.ralph/GOAL.md <<'EOF'
Create add.py in the project root exposing add(a, b) returning a + b.
Acceptance (VALIDATE must run this and see it pass):
  python3 -c "import add; assert add.add(2,3)==5; assert add.add(-1,1)==0; print('OK')"
exits 0 and prints OK. Only add.py is required. No packages.
EOF
export RALPH_PLAN_CONTEXT_WINDOW=32768 RALPH_EXEC_CONTEXT_WINDOW=32768   # your models' windows
bin/ralph /tmp/ralph-smoke

jq -r .phase /tmp/ralph-smoke/.ralph/STATE.json     # -> COMPLETE
( cd /tmp/ralph-smoke && python3 -c "import add; assert add.add(2,3)==5; print('OK')" )
```

Cap/halt checks (each independent):

```bash
RALPH_MAX_TURNS=2 bin/ralph /tmp/ralph-impossible        # phase exits TURN_CAP
RALPH_PLAN_CONTEXT_WINDOW=2000 RALPH_CONTEXT_PCT=0.5 \
  bin/ralph /tmp/ralph-ctx                               # first (PLAN) turn -> CTX_CAP
touch /tmp/ralph-smoke/.ralph/STOP                       # -> HALTED_STOP, exit 0
RALPH_PI_BIN=/usr/bin/false bin/ralph /tmp/ralph-smoke   # -> HALTED_PI_ERROR
```

## Caveats

- **`pi` writes its own artifacts into the target.** `pi`'s ambient memory/
  context behavior can drop files (e.g. a `MEMORY.md`) into the target's
  working directory, unrelated to your goal. These are harmless to the run
  but pollute the repo. Scope `pi`'s config if you need clean targets:
  `PI_CODING_AGENT_DIR=<isolated dir> bin/ralph <target>`, and/or add such
  files to the target's `.gitignore`.
- **The model decides "done".** VALIDATE emits `<goal-complete/>` and the
  orchestrator re-verifies the backlog is drained — but correctness still
  depends on your `GOAL.md` acceptance check being concrete and runnable.
  Write acceptance criteria as an exact command with an observable result.
