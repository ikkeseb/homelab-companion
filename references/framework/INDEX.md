# The forensics framework — four principles

This is the core of `homelab-companion`. The pitfall catalog
illustrates the framework; the framework is what you apply when no
pitfall matches. Run these four questions against any homelab
diagnosis or proposed fix before committing to it.

## The four principles

| # | Principle | Question to ask | File |
|---|---|---|---|
| 1 | Data layer over surface layer | What does the layer beneath the tool's output actually say? | [01-data-vs-surface.md](01-data-vs-surface.md) |
| 2 | Ordering, not arg-tuning | Does the bug live in the call's *position*, not its *flags*? | [02-ordering-vs-args.md](02-ordering-vs-args.md) |
| 3 | Read-only before mutation | Have I proven the next command doesn't write before I run it? | [03-readonly-first.md](03-readonly-first.md) |
| 4 | Name the default before answering | What's the plausible-but-wrong default I'm about to reach for? | [04-debias-prompt.md](04-debias-prompt.md) |

## How the principles compose

The four principles are not a checklist to march through
mechanically. They're framings that let you notice a class of
mistake before it lands. In practice:

- **Principles 1 and 4 catch wrong diagnoses.** Surface-layer
  trust and default-answer reach are the two most common ways an
  LLM commits early to the wrong root cause. Apply them to any
  hypothesis before treating it as load-bearing.
- **Principles 2 and 3 catch wrong fixes.** Even with the right
  diagnosis, the proposed fix often tunes args inside a broken
  shape, or runs a "diagnostic" that destroys evidence. Apply
  them to any command or code change before suggesting it.

A single incident often touches all four. The
[ufw-docker bridge drop](../pitfalls/ufw-docker-bridge-drop.md)
case: principle 1 reframes "the firewall is enforced" (surface)
to "the source IP is on a bridge subnet that has no rule" (data
layer). Principle 4 catches the default *"open the port"* answer
and routes around it. Principle 2 picks the structural fix
(allow the source subnet, or move to host networking) over the
arg-level *"add allow 8080"*. Principle 3 keeps the
diagnostic walk read-only — `ufw status verbose`, `docker
network inspect`, `ip addr` — before any mutation.

## When the catalog is silent

The principles are designed to give a useful answer even when no
catalog pitfall matches the symptom. A novel failure mode in a
service the catalog doesn't cover still benefits from "what does
the data layer say", "is this an ordering bug or an arg-tuning
bug", and "is the next command read-only". The framework is the
skill's primary value; the catalog is worked examples of the
framework applied.

If the symptom genuinely matches a catalog pitfall, link it
during analysis and follow that file's specifics. Otherwise,
apply the principles directly and surface the reasoning so the
user can see the framework being used.

## When the framework is silent

Some bugs are flat — wrong config value, missing dependency,
typo. The framework doesn't have to fire on every interaction.
If the answer is obvious and the action is reversible, just
answer. The framework exists for the cases where it isn't and
where it isn't, respectively.

Don't force-fit. A principle that doesn't apply to the situation
at hand is silence, not a failed match.
