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
