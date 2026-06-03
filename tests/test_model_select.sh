#!/usr/bin/env bash
# tests/test_model_select.sh — tests for the two-model planner/executor split
# in lib/common.sh (ralph_model_args + ralph_context_window).
set -euo pipefail

RALPH_HOME="$(cd "$(dirname "$0")/.." && pwd)"

pass() { printf 'PASS: %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# join args onto one line for easy comparison
_args() { ralph_model_args "$1" | tr '\n' ' ' | sed 's/ *$//'; }

source "$RALPH_HOME/lib/common.sh"

# Test 1: documented defaults are in effect
[ "$RALPH_PLAN_MODEL" = "quality" ]           || fail "RALPH_PLAN_MODEL default should be quality (got $RALPH_PLAN_MODEL)"
[ "$RALPH_EXEC_MODEL" = "code" ]              || fail "RALPH_EXEC_MODEL default should be code (got $RALPH_EXEC_MODEL)"
[ "$RALPH_PLAN_CONTEXT_WINDOW" = "131072" ]  || fail "RALPH_PLAN_CONTEXT_WINDOW default should be 131072"
[ "$RALPH_EXEC_CONTEXT_WINDOW" = "65536" ]   || fail "RALPH_EXEC_CONTEXT_WINDOW default should be 65536"
pass "defaults: plan=quality/131072 exec=code/65536"

# Test 2: PLAN and VALIDATE resolve to the plan model + window; IMPLEMENT to exec
[ "$(_args plan)" = "--model quality" ]      || fail "plan should use --model quality (got '$(_args plan)')"
[ "$(_args validate)" = "--model quality" ]  || fail "validate should use --model quality (got '$(_args validate)')"
[ "$(_args implement)" = "--model code" ]    || fail "implement should use --model code (got '$(_args implement)')"
[ "$(ralph_context_window plan)" = "131072" ]      || fail "plan window should be 131072"
[ "$(ralph_context_window validate)" = "131072" ]  || fail "validate window should be 131072"
[ "$(ralph_context_window implement)" = "65536" ]  || fail "implement window should be 65536"
pass "phase -> model/window mapping (plan/validate=plan, implement=exec)"

# Test 3: RALPH_PROVIDER applies to both models when set
export RALPH_PROVIDER=ollama
[ "$(_args plan)" = "--model quality --provider ollama" ] \
  || fail "provider should apply to plan (got '$(_args plan)')"
[ "$(_args implement)" = "--model code --provider ollama" ] \
  || fail "provider should apply to implement (got '$(_args implement)')"
unset RALPH_PROVIDER
pass "RALPH_PROVIDER applies to both models"

# Test 4: overrides are honored
export RALPH_PLAN_MODEL=big RALPH_EXEC_MODEL=fast
export RALPH_PLAN_CONTEXT_WINDOW=200000 RALPH_EXEC_CONTEXT_WINDOW=32768
[ "$(_args plan)" = "--model big" ]          || fail "plan override not honored (got '$(_args plan)')"
[ "$(_args implement)" = "--model fast" ]    || fail "exec override not honored (got '$(_args implement)')"
[ "$(ralph_context_window plan)" = "200000" ]     || fail "plan window override not honored"
[ "$(ralph_context_window implement)" = "32768" ] || fail "exec window override not honored"
pass "model/window overrides honored"

echo "All tests passed."
