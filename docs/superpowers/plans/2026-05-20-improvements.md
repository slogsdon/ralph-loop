# ralph-loop: LLM Excerpt Journaling + Reset Subcommand — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add per-turn LLM excerpt journaling to `JOURNAL.md` and a `ralph reset` subcommand that clears harness state so the same target directory can be aimed at a new goal.

**Architecture:** Two independent, surgical changes to the existing bash harness. Feature 1 extracts a `_journal_llm_excerpt` helper into `lib/phase.sh` and wires it into `run_phase` immediately after `pi_assistant_text` is called (before signal checks, so aborted turns are still visible). Feature 2 adds a `do_reset` function and a `reset` dispatch case to `bin/ralph`. Tests live in `tests/` as plain bash assertion scripts with no external dependencies.

**Tech Stack:** bash 3.2+, jq, POSIX tools (`head -c`, `tr`, `diff`)

---

## File Map

| File | Change |
|---|---|
| `lib/common.sh` | Add `RALPH_JOURNAL_EXCERPT_LEN` env default |
| `lib/phase.sh` | Add `_journal_llm_excerpt` helper; call it in `run_phase` |
| `bin/ralph` | Add `do_reset()`, update `usage()`, relax arg check, add `reset` dispatch |
| `tests/test_reset.sh` | New: bash tests for `do_reset` |
| `tests/test_excerpt.sh` | New: bash tests for `_journal_llm_excerpt` |
| `docs/README.md` | Document new env var and `reset` subcommand |

---

### Task 1: Write failing tests for `do_reset`

**Files:**
- Create: `tests/test_reset.sh`

- [ ] **Step 1: Create `tests/test_reset.sh`**

```bash
mkdir -p /Users/shane/Code/ralph-loop/tests
```

Write `tests/test_reset.sh` with the content below:

```bash
#!/usr/bin/env bash
# tests/test_reset.sh — tests for `ralph reset` subcommand
set -euo pipefail

RALPH_HOME="$(cd "$(dirname "$0")/.." && pwd)"
RALPH_BIN="$RALPH_HOME/bin/ralph"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass() { printf 'PASS: %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

_scaffold() {
  local d="$1"
  mkdir -p "$d/.ralph/sessions" "$d/.ralph/logs"
  echo '{"version":1,"phase":"COMPLETE","iteration":3}' > "$d/.ralph/STATE.json"
  echo "# Plan content" > "$d/.ralph/PLAN.md"
  cp "$RALPH_HOME/templates/BACKLOG.md" "$d/.ralph/BACKLOG.md"
  echo "- [x] done task" >> "$d/.ralph/BACKLOG.md"
  echo "validation failure text" > "$d/.ralph/VALIDATION.md"
  echo "My specific goal for this run" > "$d/.ralph/GOAL.md"
  echo "2026-05-20T00:00:00Z  INIT" > "$d/.ralph/JOURNAL.md"
  touch "$d/.ralph/sessions/abc_def123.jsonl"
  touch "$d/.ralph/logs/1-plan-1.jsonl"
}

# Test 1: full reset clears state, resets GOAL.md to template, preserves JOURNAL + logs
T1="$TMP/t1"; mkdir "$T1"; _scaffold "$T1"
"$RALPH_BIN" reset "$T1"
[ ! -f "$T1/.ralph/STATE.json" ]    || fail "STATE.json should be deleted"
[ ! -s "$T1/.ralph/PLAN.md" ]       || fail "PLAN.md should be empty"
[ ! -s "$T1/.ralph/VALIDATION.md" ] || fail "VALIDATION.md should be empty"
diff "$T1/.ralph/BACKLOG.md" "$RALPH_HOME/templates/BACKLOG.md" >/dev/null \
  || fail "BACKLOG.md should match template"
diff "$T1/.ralph/GOAL.md" "$RALPH_HOME/templates/GOAL.md" >/dev/null \
  || fail "GOAL.md should match template after full reset"
[ ! -f "$T1/.ralph/sessions/abc_def123.jsonl" ] \
  || fail "sessions/ contents should be wiped"
[ -f "$T1/.ralph/logs/1-plan-1.jsonl" ] \
  || fail "logs/ should be preserved"
[ -s "$T1/.ralph/JOURNAL.md" ] \
  || fail "JOURNAL.md should be preserved and non-empty"
grep -q "RESET" "$T1/.ralph/JOURNAL.md" \
  || fail "JOURNAL.md should contain a RESET entry"
pass "full reset"

# Test 2: --keep-goal preserves GOAL.md, still wipes state
T2="$TMP/t2"; mkdir "$T2"; _scaffold "$T2"
"$RALPH_BIN" reset "$T2" --keep-goal
[ ! -f "$T2/.ralph/STATE.json" ] \
  || fail "STATE.json should be deleted even with --keep-goal"
grep -q "My specific goal" "$T2/.ralph/GOAL.md" \
  || fail "GOAL.md should be preserved with --keep-goal"
pass "reset --keep-goal"

# Test 3: reset on a dir with no .ralph/ exits non-zero
T3="$TMP/t3"; mkdir "$T3"
if "$RALPH_BIN" reset "$T3" 2>/dev/null; then
  fail "should exit non-zero when .ralph/ is absent"
fi
pass "reset with no .ralph/ exits non-zero"

echo "All tests passed."
```

- [ ] **Step 2: Make executable**

```bash
chmod +x /Users/shane/Code/ralph-loop/tests/test_reset.sh
```

---

### Task 2: Run reset tests — verify they fail

**Files:** (none changed)

- [ ] **Step 1: Run**

```bash
cd /Users/shane/Code/ralph-loop && bash tests/test_reset.sh
```

Expected: exits non-zero. The `reset` arg is not yet handled, so ralph will print usage and exit 64 on T1. Any failure here confirms the tests exercise real behaviour before the implementation exists.

---

### Task 3: Implement `do_reset()` and update arg parsing in `bin/ralph`

**Files:**
- Modify: `bin/ralph`

- [ ] **Step 1: Add `do_reset()` to `bin/ralph`**

Add the function between `usage()` and the argument check (after line 36 `}`  that closes `usage()`, before line 38 `[ $# -eq 1 ]`):

```bash
do_reset() {
  local target="$1" keep_goal="${2:-0}"
  [ -d "$target" ] || die "target is not a directory: $target"
  RALPH_TARGET="$(cd "$target" && pwd)"; export RALPH_TARGET
  local rdir="$RALPH_TARGET/.ralph"
  [ -d "$rdir" ] || die "no .ralph/ found in $target — run ralph $target first to initialise"
  rm -f "$rdir/STATE.json"
  : > "$rdir/PLAN.md"
  : > "$rdir/VALIDATION.md"
  cp "$RALPH_HOME/templates/BACKLOG.md" "$rdir/BACKLOG.md"
  rm -rf "$rdir/sessions"
  mkdir -p "$rdir/sessions"
  if [ "$keep_goal" -eq 0 ]; then
    cp "$RALPH_HOME/templates/GOAL.md" "$rdir/GOAL.md"
  fi
  journal "RESET state cleared (keep_goal=$keep_goal)"
  log "reset complete: $rdir"
}
```

- [ ] **Step 2: Update `usage()` in `bin/ralph`**

Replace the current `usage()` body (lines 30–35):

```bash
usage() {
  cat <<'EOF'
Usage: ralph <target-project-dir>
       ralph reset <target-project-dir> [--keep-goal]

First run scaffolds <target>/.ralph/ and writes a GOAL.md template — fill it
in, then re-run. See docs/README.md for the env-var surface and safety model.

reset: clear harness state so the target can be used with a new goal.
       --keep-goal preserves the existing GOAL.md (useful for retrying
       the same goal after a bad run).
EOF
}
```

- [ ] **Step 3: Update arg check and add reset dispatch**

Replace (lines 38–39):
```bash
[ $# -eq 1 ] || { usage; exit 64; }
case "$1" in -h|--help) usage; exit 0;; esac
```

With:
```bash
[ $# -ge 1 ] || { usage; exit 64; }
case "$1" in -h|--help) usage; exit 0;; esac

if [ "$1" = "reset" ]; then
  [ $# -ge 2 ] || { usage; exit 64; }
  _keep_goal=0
  [ "${3:-}" = "--keep-goal" ] && _keep_goal=1
  do_reset "$2" "$_keep_goal"
  exit 0
fi
```

---

### Task 4: Run reset tests — verify they pass, commit

**Files:** (none changed)

- [ ] **Step 1: Run**

```bash
cd /Users/shane/Code/ralph-loop && bash tests/test_reset.sh
```

Expected output:
```
PASS: full reset
PASS: reset --keep-goal
PASS: reset with no .ralph/ exits non-zero
All tests passed.
```

- [ ] **Step 2: Commit**

```bash
git add bin/ralph tests/test_reset.sh
git commit -m "feat: add ralph reset subcommand with --keep-goal flag"
```

---

### Task 5: Write failing tests for `_journal_llm_excerpt`

**Files:**
- Create: `tests/test_excerpt.sh`

- [ ] **Step 1: Write `tests/test_excerpt.sh`**

```bash
#!/usr/bin/env bash
# tests/test_excerpt.sh — tests for _journal_llm_excerpt helper in lib/phase.sh
set -euo pipefail

RALPH_HOME="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass() { printf 'PASS: %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# Bootstrap a minimal .ralph/ so journal() has somewhere to write
export RALPH_TARGET="$TMP"
mkdir -p "$TMP/.ralph"
: > "$TMP/.ralph/JOURNAL.md"

source "$RALPH_HOME/lib/common.sh"
source "$RALPH_HOME/lib/state.sh"
source "$RALPH_HOME/lib/phase.sh"

# Test 1: excerpt appears in JOURNAL.md, truncated to RALPH_JOURNAL_EXCERPT_LEN
: > "$TMP/.ralph/JOURNAL.md"
RALPH_JOURNAL_EXCERPT_LEN=20
_journal_llm_excerpt "plan" "1" "Hello world this is a longer message that will be truncated"
grep -q "phase=plan turn=1 llm:" "$TMP/.ralph/JOURNAL.md" \
  || fail "excerpt entry not found in journal"
line="$(grep 'llm:' "$TMP/.ralph/JOURNAL.md")"
excerpt_part="${line##*llm: }"
[ "${#excerpt_part}" -le 20 ] \
  || fail "excerpt longer than RALPH_JOURNAL_EXCERPT_LEN=20 (got ${#excerpt_part} chars)"
pass "excerpt appears truncated in journal"

# Test 2: newlines in assistant text are collapsed to a single journal line
: > "$TMP/.ralph/JOURNAL.md"
RALPH_JOURNAL_EXCERPT_LEN=250
_journal_llm_excerpt "implement" "2" "$(printf 'line one\nline two\nline three')"
line_count="$(grep -c 'llm:' "$TMP/.ralph/JOURNAL.md")"
[ "$line_count" -eq 1 ] \
  || fail "multiline text should produce exactly 1 journal line (got $line_count)"
pass "multiline text collapsed to single journal line"

# Test 3: RALPH_JOURNAL_EXCERPT_LEN=0 disables journaling entirely
: > "$TMP/.ralph/JOURNAL.md"
RALPH_JOURNAL_EXCERPT_LEN=0
_journal_llm_excerpt "validate" "1" "should not appear"
[ ! -s "$TMP/.ralph/JOURNAL.md" ] \
  || fail "excerpt should not be written when RALPH_JOURNAL_EXCERPT_LEN=0"
pass "excerpt disabled with len=0"

# Test 4: empty text produces no journal entry
: > "$TMP/.ralph/JOURNAL.md"
RALPH_JOURNAL_EXCERPT_LEN=250
_journal_llm_excerpt "plan" "3" ""
[ ! -s "$TMP/.ralph/JOURNAL.md" ] \
  || fail "empty text should not produce a journal entry"
pass "empty text produces no journal entry"

echo "All tests passed."
```

- [ ] **Step 2: Make executable**

```bash
chmod +x /Users/shane/Code/ralph-loop/tests/test_excerpt.sh
```

---

### Task 6: Run excerpt tests — verify they fail

**Files:** (none changed)

- [ ] **Step 1: Run**

```bash
cd /Users/shane/Code/ralph-loop && bash tests/test_excerpt.sh
```

Expected: exits non-zero. `_journal_llm_excerpt` is not yet defined in `phase.sh`, so the first call errors. Any failure here confirms the tests are live.

---

### Task 7: Add `RALPH_JOURNAL_EXCERPT_LEN` to `lib/common.sh` and `_journal_llm_excerpt` to `lib/phase.sh`

**Files:**
- Modify: `lib/common.sh`
- Modify: `lib/phase.sh`

- [ ] **Step 1: Add env default to `lib/common.sh`**

After the `RALPH_RETRY_TRANSIENT` line (line 10), add:

```bash
: "${RALPH_JOURNAL_EXCERPT_LEN:=250}"  # chars of assistant text per turn logged to JOURNAL.md; 0 = off
```

- [ ] **Step 2: Add `_journal_llm_excerpt` to `lib/phase.sh`**

Add the function at the top of `lib/phase.sh`, after the comment header block and before the existing `_fge()` definition (before line 11):

```bash
_journal_llm_excerpt() {
  local phase="$1" turn="$2" txt="$3"
  [ "${RALPH_JOURNAL_EXCERPT_LEN:-250}" -gt 0 ] || return 0
  [ -n "$txt" ] || return 0
  local excerpt
  excerpt="$(printf '%s' "$txt" | head -c "${RALPH_JOURNAL_EXCERPT_LEN:-250}" | tr '\n' ' ')"
  journal "phase=$phase turn=$turn llm: ${excerpt}"
}
```

---

### Task 8: Wire `_journal_llm_excerpt` into `run_phase`

**Files:**
- Modify: `lib/phase.sh`

- [ ] **Step 1: Call `_journal_llm_excerpt` after `pi_assistant_text` in `run_phase`**

In `lib/phase.sh`, find the line (currently line 81):
```bash
    local txt; txt="$(pi_assistant_text "$out")"
```

Change it to:
```bash
    local txt; txt="$(pi_assistant_text "$out")"
    _journal_llm_excerpt "$phase" "$turn" "$txt"
```

---

### Task 9: Run excerpt tests — verify they pass, commit

**Files:** (none changed)

- [ ] **Step 1: Run**

```bash
cd /Users/shane/Code/ralph-loop && bash tests/test_excerpt.sh
```

Expected output:
```
PASS: excerpt appears truncated in journal
PASS: multiline text collapsed to single journal line
PASS: excerpt disabled with len=0
PASS: empty text produces no journal entry
All tests passed.
```

- [ ] **Step 2: Commit**

```bash
git add lib/common.sh lib/phase.sh tests/test_excerpt.sh
git commit -m "feat: add per-turn LLM excerpt journaling with RALPH_JOURNAL_EXCERPT_LEN"
```

---

### Task 10: Update `docs/README.md`

**Files:**
- Modify: `docs/README.md`

- [ ] **Step 1: Add `RALPH_JOURNAL_EXCERPT_LEN` to the Configuration table**

In the configuration table (around line 107), add a row after the `RALPH_RETRY_TRANSIENT` row:

```markdown
| `RALPH_JOURNAL_EXCERPT_LEN` | `250` | chars of assistant text appended to `JOURNAL.md` per turn; `0` disables |
```

- [ ] **Step 2: Add a `## Resetting for a new goal` section**

Add after the `## Monitoring a run` section (before `## Configuration`):

```markdown
## Resetting for a new goal

After a run completes or halts, reuse the same target directory for a new goal:

```bash
ralph reset /path/to/target-project             # wipes state + resets GOAL.md to template
ralph reset /path/to/target-project --keep-goal # wipes state, keeps existing GOAL.md
```

`JOURNAL.md` and `logs/` are always preserved as audit history. `reset` requires
`.ralph/` to exist (initialise with a regular `ralph` run first if needed).
After a full reset, fill in `.ralph/GOAL.md` then re-run `ralph <target>` to start fresh.
```

- [ ] **Step 3: Commit**

```bash
git add docs/README.md
git commit -m "docs: document RALPH_JOURNAL_EXCERPT_LEN and ralph reset subcommand"
```
