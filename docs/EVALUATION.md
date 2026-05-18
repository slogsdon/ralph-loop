# ralph-loop — 60-Day Evaluation

**OKR linkage:** O3 KR2 — "Ship and document 2+ agentic workflow automations,
each with a 60-day written evaluation." This document is the written
evaluation for `ralph-loop`.

- **Automation:** `ralph-loop` — unattended PLAN/IMPLEMENT/VALIDATE loop on `pi`.
- **Evaluation window:** START_DATE → +60 days (fill in on first real run).
- **Owner:** Shane.

## Hypothesis

Driving real, bounded development goals through an unattended Ralph loop
produces correct, verified results with materially less human time than
hands-on implementation, without runaway cost or quality regressions.

## Success threshold (decide up front)

`ralph-loop` is judged successful at day 60 if **all** hold:

- ≥ 70% of attempted goals reach `COMPLETE` with green goal-level validation
  and no human code edits mid-run.
- Mean human intervention ≤ 1 touch per completed goal (excluding writing
  `GOAL.md` and the final review).
- Zero uncontrolled runs: every run ends in `COMPLETE` or a `HALTED_*` state;
  no manual kills due to the loop misbehaving.
- No validated correctness/security regression shipped from a `COMPLETE` run.

## Metrics (aggregate, fill at day 30 and day 60)

| Metric | Day 30 | Day 60 |
|---|---|---|
| Goals attempted | | |
| Goals completed unattended | | |
| Goals halted (`HALTED_*`, by type) | | |
| Mean human interventions / completed goal | | |
| Mean wall-clock / completed goal | | |
| Mean iterations / completed goal | | |
| Mean turns / phase | | |
| TURN_CAP / CTX_CAP hits | | |
| Est. token cost / completed goal | | |
| Correctness/security issues escaped | | |

### Failure taxonomy (tally)

| Class | Count | Notes |
|---|---|---|
| Bad/insufficient plan | | |
| Implementation incorrect | | |
| Validation false-positive | | |
| Validation false-negative / thrash | | |
| Stuck (3× identical) | | |
| pi/tooling error | | |
| Context exhaustion before progress | | |

## Per-run log

One row per `ralph` run; source data is `<target>/.ralph/JOURNAL.md` +
`STATE.json`.

| Date | Target / goal (1 line) | Iterations | End state | Human touches | Wall-clock | Notes |
|---|---|---|---|---|---|---|
| | | | | | | |

## Weekly check-ins

Brief: what was run, what worked, what was tuned (env vars, prompts), one
representative `JOURNAL.md` excerpt.

- **Week 1 (days 1–7):**
- **Week 2 (days 8–14):**
- **Week 3 (days 15–21):**
- **Week 4 (days 22–28):**
- **Day 30 checkpoint** — interim verdict, tuning decisions:
- **Week 5 (days 29–35):**
- **Week 6 (days 36–42):**
- **Week 7 (days 43–49):**
- **Week 8 (days 50–56):**
- **Week 9 (days 57–60):**

## Day-60 verdict

- Threshold met? (yes/no, per criterion)
- Keep / iterate / retire:
- Highest-leverage improvement identified:
- Recommendation for the second O3 KR2 automation:
