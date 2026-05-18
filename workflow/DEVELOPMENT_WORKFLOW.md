# Development Workflow (autonomous adaptation)

This is the overarching process for every phase of this loop. It is adapted
from Shane's `Context/Development Workflow` note — the original expresses each
step as a Claude Code skill invocation; here those steps are restated as the
underlying *process*, because this loop drives the `pi` agent which cannot
invoke those skills. Follow the spirit of each step.

## The loop's shape
PLAN → IMPLEMENT → VALIDATE, repeated until the goal is verifiably met.
Durable state lives only in `.ralph/*.md` files — never assume memory of a
previous phase; read the files.

## 1. Specify before building
Treat `GOAL.md` as the spec. Restate the objective and its acceptance
criteria in concrete, testable terms before planning work. If the goal is
ambiguous, choose the simplest defensible interpretation and record the
assumption rather than stalling.

## 2. Plan in small, verifiable slices
Decompose into the smallest tasks that each (a) deliver one coherent change
and (b) can be independently verified by a concrete command or observation.
Order by dependency. Prefer the boring, minimal path. No speculative scope.

## 3. Build test-first
For each task: write a failing test that encodes the acceptance criterion,
then the minimal implementation to make it pass, then refactor only if it
improves clarity. Keep changes surgical — touch only what the task requires.
Honor the target project's existing conventions (`CLAUDE.md`, `AGENTS.md`,
`README`, lint/format/build tooling).

## 4. Debug systematically
When something breaks: reproduce it, localize the root cause, fix the cause
(not the symptom), then add or extend a test that guards against regression.
Do not paper over failures or loosen assertions to get green.

## 5. Validate with evidence
"Done" is a claim that requires proof. Never mark work complete without
running the actual check and observing it pass. Beyond correctness, do a
quick pass for obvious security issues (input validation, injection, secrets,
least privilege) and for clarity/maintainability. Prefer a false-negative
(fail and explain) over a false-positive (pass on assumption).

## 6. Ship cleanly
When the whole goal is verified: ensure the working tree is coherent, tests
pass, and nothing half-finished remains. Leave the project in a releasable
state. Conventional-commit style; never reference the agent in commit text.

## Operating constraints (all phases)
- Unattended: no human will answer. Decide, act, record assumptions.
- Scope discipline: do not modify code, comments, or files orthogonal to the
  current task. No unsolicited refactors.
- Simplicity: if 100 lines would do, do not write 1000. Resist cleverness.
- Surface confusion in your output, but still make forward progress — the
  next phase reads what you leave in the `.ralph/` files.
