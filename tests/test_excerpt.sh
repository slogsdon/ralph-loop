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

# Test 5: a multibyte UTF-8 char sliced at the excerpt boundary must not crash
# the helper (head -c can split a multibyte char; a UTF-8-locale tr would abort
# on the partial byte and, under set -e, kill the whole loop).
: > "$TMP/.ralph/JOURNAL.md"
RALPH_JOURNAL_EXCERPT_LEN=4   # slices "caf<é>" mid-character (é = 0xC3 0xA9)
_journal_llm_excerpt "implement" "5" "caf$(printf '\xc3\xa9') and emoji $(printf '\xf0\x9f\x98\x80')"
grep -q "phase=implement turn=5 llm:" "$TMP/.ralph/JOURNAL.md" \
  || fail "helper crashed or wrote nothing on mid-multibyte slice"
pass "mid-multibyte slice does not crash the helper"

echo "All tests passed."
