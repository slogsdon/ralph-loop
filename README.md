# ralph

Unattended agentic coding loop. Give it a project directory and a goal; it runs `PLAN → IMPLEMENT → VALIDATE` until the goal is provably met — no babysitting required.

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

Open `.ralph/GOAL.md` and describe what you want built. The key is a **concrete acceptance command** — something VALIDATE can actually run.

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

By default ralph uses whatever model `pi` is already configured for (typically a local model via LM Studio or Ollama). Set your model's context window so the loop paces itself correctly:

```bash
export RALPH_CONTEXT_WINDOW=32768   # match your local model
ralph /path/to/my-project
```

To use a cloud model instead:

```bash
export RALPH_MODEL=claude-sonnet RALPH_PROVIDER=anthropic RALPH_CONTEXT_WINDOW=200000
ralph /path/to/my-project
```

---

## Key config

| Variable | Default | What it does |
|---|---|---|
| `RALPH_CONTEXT_WINDOW` | `200000` | **Set this to your model's window** |
| `RALPH_MAX_TURNS` | `30` | Per-phase turn cap |
| `RALPH_MAX_ITERATIONS` | `50` | Global outer-loop cap |
| `RALPH_MODEL` / `RALPH_PROVIDER` | unset | Pin a specific model |

Full reference: [`docs/README.md`](docs/README.md)
