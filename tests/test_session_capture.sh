#!/usr/bin/env bash
# tests/test_session_capture.sh — tests for _pi_capture_session_uuid in lib/pi.sh.
# Regression: a stale/orphan session lingering in the session dir must not
# shadow the session pi just created (mtime, not alphabetical, wins).
set -euo pipefail

RALPH_HOME="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass() { printf 'PASS: %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

source "$RALPH_HOME/lib/common.sh"
source "$RALPH_HOME/lib/pi.sh"

STALE="2026-01-01T00-00-00-000Z_019aaaaa-1111-2222-3333-444444444444.jsonl"
ACTIVE="2026-06-03T21-22-11-795Z_019bbbbb-5555-6666-7777-888888888888.jsonl"
STALE_UUID="019aaaaa-1111-2222-3333-444444444444"
ACTIVE_UUID="019bbbbb-5555-6666-7777-888888888888"

# Test 1: orphan present, both files appear during the run (before was empty).
# STALE sorts alphabetically first but is older by mtime — the active session
# (newer mtime) must win.
S1="$TMP/s1"; mkdir -p "$S1"
before=""                                   # dir freshly wiped at phase entry
touch -t 202601010000 "$S1/$STALE"          # orphan, older
touch -t 202606032122 "$S1/$ACTIVE"         # pi's real session, newer
got="$(_pi_capture_session_uuid "$S1" "$before")"
[ "$got" = "$ACTIVE_UUID" ] \
  || fail "expected active uuid (newest mtime), got '$got'"
pass "newest-by-mtime wins over alphabetically-earlier orphan"

# Test 2: stale file pre-existed (in $before); only the active file is new.
S2="$TMP/s2"; mkdir -p "$S2"
touch -t 202601010000 "$S2/$STALE"
before="$(ls "$S2"/*.jsonl 2>/dev/null | sort || true)"   # snapshot WITH stale
touch -t 202606032122 "$S2/$ACTIVE"                       # appears during run
got="$(_pi_capture_session_uuid "$S2" "$before")"
[ "$got" = "$ACTIVE_UUID" ] \
  || fail "pre-existing stale should be excluded; expected active, got '$got'"
pass "session present in \$before is excluded from capture"

# Test 3: no new session created (before == after) -> empty UUID
S3="$TMP/s3"; mkdir -p "$S3"
touch -t 202601010000 "$S3/$STALE"
before="$(ls "$S3"/*.jsonl 2>/dev/null | sort || true)"
got="$(_pi_capture_session_uuid "$S3" "$before")"
[ -z "$got" ] || fail "no new file should yield empty uuid, got '$got'"
pass "no new session yields empty uuid"

# Test 4: empty dir, single new session -> that UUID
S4="$TMP/s4"; mkdir -p "$S4"
before=""
touch -t 202606032122 "$S4/$ACTIVE"
got="$(_pi_capture_session_uuid "$S4" "$before")"
[ "$got" = "$ACTIVE_UUID" ] || fail "single new session not captured, got '$got'"
pass "single new session captured"

echo "All tests passed."
