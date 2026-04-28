# Iteration 1 — benchmark summary

Generated 2026-04-28 via `/skill-creator` after the v0.1 build.

## Headline numbers

| Metric | with skill | without skill | delta |
|---|---|---|---|
| **Pass rate** | **22/22 (100%)** | **4/22 (18%)** | **+83 pp** |
| Time per eval | 62s avg | 45s avg | +17s |
| Tokens per eval | 25k avg | 16.5k avg | +8.6k |

Each test case runs the same prompt twice — once with the skill
loaded, once without. The "without" arm is what a Claude Code
session looks like for a homelab user who doesn't have the skill
installed. The "with" arm is what they'd see after installing.

## Per-eval breakdown

| Eval | Domain | with skill | without skill | Notable |
|---|---|---|---|---|
| 0 | Preventive — ufw-docker bridge drop | 5/5 | 0/5 | Baseline fell into the canonical "Docker bypasses ufw" trap |
| 1 | Preventive — gluetun + qBit auto-recovery | 5/5 | 0/5 | Baseline missed netns-orphan; wrote about VPN bypass / DNS leaks instead |
| 2 | Retrospective — git script intermittent fail | 6/6 | 3/6 | Weakest gap — general git knowledge gets baseline halfway |
| 3 | Retrospective — qBit unreachable | 6/6 | 1/6 | Baseline produced a confidently-wrong mechanism (tunnel stall vs netns orphan) |

## What the numbers mean

- **The skill is doing what it claims.** 100% pass rate on the
  with-skill arm means the catalog covers the symptoms and the
  PM template + prompts produce structured, useful output.

- **The differentiator is real.** 18% baseline pass rate
  confirms these are pitfalls a generic Claude Code session
  reliably mishandles — exactly the LLM-default-trap shape
  the catalog targets.

- **Eval-3 is the most interesting result.** Both arms produced
  structured post-mortems. Without the skill, the baseline
  confidently wrote the *wrong* mechanism — gluetun's tunnel
  stalled, fix the healthcheck. With the skill, the right
  mechanism — Docker doesn't re-wire the child's netns when
  the parent restarts. A user following the wrong-mechanism
  PM would set up monitoring that wouldn't actually catch the
  failure mode.

- **Eval-2 shows where the catalog adds less.** When general
  git knowledge gets you to "reorder operations", the skill's
  marginal value drops. It still wins by generalizing the
  pattern (sweep other scripts) and by explicitly rejecting
  `--autostash` as the wrong fix — both things baseline didn't
  produce — but the gap is narrower.

## Cost trade-off

The skill uses ~52% more tokens (25k vs 16.5k) and runs ~37%
slower (62s vs 45s). That cost comes from progressive disclosure —
loading INDEX.md, then the matching pitfall file, then the PM
template, then sometimes a worked example. It's the cost of being
right about the right thing.

## Files

- [`benchmark.json`](benchmark.json) — full structured data
  (per-run pass/fail with evidence quotes for every assertion)
- [`review.html`](review.html) — interactive viewer (open in
  browser)
