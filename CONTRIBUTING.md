# Contributing

## Setup

You need `pi` (v0.75+), bash 3.2+, and the POSIX tools listed in the README.
The harness has no language runtime dependency. That's the target project's
concern.

Clone the repo and optionally symlink the binary:

```bash
git clone https://github.com/slogsdon/ralph-loop
cd ralph-loop
ln -sfn "$PWD/bin/ralph" /opt/homebrew/bin/ralph
```

## Smoke test

The smoke test in `docs/README.md` is the baseline integration check. It needs
only `python3` and a working `pi` setup. Run it before and after any change.

## Layout

```
bin/ralph        orchestrator: outer state machine, bootstrap, reset
lib/
  common.sh      env defaults, logging, shared constants
  state.sh       STATE.json read/write wrappers
  pi.sh          pi invocation, session resume, context fraction extraction
  safety.sh      stop/stuck/pi-error halt checks
  phase.sh       inner per-phase resume-loop (turn cap + context cap)
prompts/         system prompt injected into each phase's pi session
templates/       scaffolded into <target>/.ralph/ on first run
workflow/        development process injected as appended system prompt
```

## What to keep in mind

No external dependencies beyond `pi` and standard POSIX tools. New behavior
should default off and be controlled by an env var. A required dependency is a
breaking change.

The prompts are as important as the shell code. A change to
`prompts/validate.md` can determine whether the loop terminates at all. Test
prompt changes against the smoke test and against a goal that previously
required multiple iterations.

## Tests

No automated test suite. The smoke test is the integration test. Write a goal
that exercises the changed behavior and confirm it reaches COMPLETE.

## PRs

Include what changed, why, and the goal you used to test it (one line). No
issue needed for small fixes. For significant changes to orchestration logic or
prompts, open an issue first to discuss the approach.
