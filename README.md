# ralph

Unattended agentic coding loop. Point it at a project directory and a goal. It runs `PLAN → IMPLEMENT → VALIDATE` until the goal is verifiably complete.

Built on [`pi`](https://pi.dev). State lives in `<target>/.ralph/` so you can Ctrl-C and resume any time.

---

## Requirements

- `pi` v0.75+
- `git`, `jq`, `awk`, `sed`, `shasum` (all on stock macOS)
- A **git repo** as the target project

---

## Install

```bash
ln -sfn "$PWD/bin/ralph" /opt/homebrew/bin/ralph
```

Or just call `bin/ralph` directly.

---

## Usage

### 1. Scaffold

Point ralph at any git repo. The first run creates `.ralph/` and drops a `GOAL.md` template, then stops.

```bash
ralph /path/to/my-project
```

### 2. Write your goal

Open `.ralph/GOAL.md` and describe what you want built. The key is a **concrete acceptance command**, something VALIDATE can actually run.

```md
Create add.py exposing add(a, b) returning a + b.
Acceptance: python3 -c "import add; assert add.add(2,3)==5; print('OK')"
exits 0 and prints OK.
```

### 3. Run

```bash
ralph /path/to/my-project
```

That's it. Ralph loops until the goal is complete or a safety limit trips.

---

## Monitoring

```bash
tail -f /path/to/my-project/.ralph/JOURNAL.md
```

One line per iteration. Done when `STATE.json` shows `"phase": "COMPLETE"`:

```bash
jq -r .phase /path/to/my-project/.ralph/STATE.json
```

---

## Stopping and resuming

- **Pause/resume:** Ctrl-C, then re-run the same command.
- **Emergency stop:** `touch /path/to/my-project/.ralph/STOP` — halts at the next iteration boundary.
- **New goal on the same project:**
  ```bash
  ralph reset /path/to/my-project           # wipes state, resets GOAL.md
  ralph reset /path/to/my-project --keep-goal  # keeps your goal, wipes run state
  ```

---

## Model selection

ralph runs a **two-model split**: a high-reasoning planner for the PLAN and VALIDATE phases, and a fast code model for IMPLEMENT. The defaults assume LiteLLM aliases over Ollama — `quality` = qwen3.6:35b-mlx, `code` = qwen2.5-coder:14b:

```bash
# the standard local setup needs no exports — these are the defaults
export RALPH_PLAN_MODEL=quality RALPH_PLAN_CONTEXT_WINDOW=131072   # PLAN + VALIDATE
export RALPH_EXEC_MODEL=code    RALPH_EXEC_CONTEXT_WINDOW=65536    # IMPLEMENT
ralph /path/to/my-project
```

Set each model's context window to match its real window so the loop paces itself correctly. `RALPH_PROVIDER` (optional) pins a provider for both models:

```bash
export RALPH_PROVIDER=ollama
ralph /path/to/my-project
```

---

## Key config

| Variable | Default | What it does |
|---|---|---|
| `RALPH_PLAN_MODEL` / `RALPH_EXEC_MODEL` | `quality` / `code` | Planner (PLAN+VALIDATE) and executor (IMPLEMENT) models |
| `RALPH_PLAN_CONTEXT_WINDOW` / `RALPH_EXEC_CONTEXT_WINDOW` | `131072` / `65536` | **Match each model's real window** |
| `RALPH_MAX_TURNS` | `30` | Per-phase turn cap |
| `RALPH_MAX_ITERATIONS` | `50` | Global outer-loop cap |
| `RALPH_PROVIDER` | unset | Pin a provider for both models |

Full reference: [`docs/README.md`](docs/README.md)
