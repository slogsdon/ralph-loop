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

# 3. Set the context window to your local model's window, then run.
export RALPH_CONTEXT_WINDOW=32768          # match your local model
bin/ralph /path/to/target-project
```

`bin/ralph -h` prints usage. Re-running resumes from `STATE.json`
(`phase`/`iteration`); Ctrl-C any time and re-run to continue.

Optional — pin a specific (e.g. cloud) model instead of the ambient default:

```bash
export RALPH_MODEL=claude-sonnet RALPH_PROVIDER=anthropic RALPH_CONTEXT_WINDOW=200000
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

## Configuration

| Env var | Default | Meaning |
|---|---|---|
| `RALPH_MAX_TURNS` | `30` | per-phase `pi` invocation cap |
| `RALPH_CONTEXT_PCT` | `0.5` | phase ends when context fraction ≥ this |
| `RALPH_CONTEXT_WINDOW` | `200000` | context window of the model `pi` actually uses — set this to your local model's window |
| `RALPH_MAX_ITERATIONS` | `50` | global outer-loop cap |
| `RALPH_MODEL` / `RALPH_PROVIDER` | unset | unset = use `pi`'s ambient (local) model; set to pin a specific model |
| `RALPH_PI_BIN` | `/opt/homebrew/bin/pi` | path to `pi` |
| `RALPH_RETRY_TRANSIENT` | `1` | transient `pi`-error retries before counting |

> **Set `RALPH_CONTEXT_WINDOW` to your model's real window.** The default
> local path needs no model flags — `pi` uses its ambient model. But the
> context cap is only meaningful if `RALPH_CONTEXT_WINDOW` matches whatever
> model `pi` actually runs. The `200000` default suits a Sonnet-class model
> and will effectively disable the cap on a smaller local model (it never
> trips), so set it explicitly (e.g. `32768`). Pin `RALPH_MODEL`/
> `RALPH_PROVIDER` only when you need a model other than the ambient one.

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
export RALPH_CONTEXT_WINDOW=32768                   # your local model's window
bin/ralph /tmp/ralph-smoke

jq -r .phase /tmp/ralph-smoke/.ralph/STATE.json     # -> COMPLETE
( cd /tmp/ralph-smoke && python3 -c "import add; assert add.add(2,3)==5; print('OK')" )
```

Cap/halt checks (each independent):

```bash
RALPH_MAX_TURNS=2 bin/ralph /tmp/ralph-impossible        # phase exits TURN_CAP
RALPH_CONTEXT_WINDOW=2000 RALPH_CONTEXT_PCT=0.5 \
  bin/ralph /tmp/ralph-ctx                               # first turn -> CTX_CAP
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
