---
name: homelab-companion
description: Use after an incident or failure when the user asks for a post-mortem, RCA, root-cause analysis, or "write up what happened" — drives a phase-by-phase post-mortem with de-bias guards (mutative-vs-readonly diagnostics) and outputs an editable Markdown draft. Also available for preventive review of homelab configs (Docker compose, ufw rules, systemd, arr-stack, YAML) when the user explicitly invokes the skill or asks for a review. Do not autotrigger on routine homelab edits or questions.
allowed-tools: Read, Write, Edit, Bash
---

# homelab-companion

A fail-mode forensics framework for homelab and self-host
operations. Same content base feeds two modes:

- **Retrospective** — drives a phase-by-phase post-mortem when
  something already broke. Auto-triggers on RCA-shaped requests.
- **Preventive** — applies the framework to a config the user is
  about to deploy. Manual invocation only; the user asks for a
  review.

The skill's primary value is the **forensics framework** in
[`references/framework/`](references/framework/INDEX.md) — four
principles that catch common LLM failure modes in homelab
debugging. The **pitfall catalog** in
[`references/pitfalls/`](references/pitfalls/INDEX.md) is worked
examples of the framework applied; not the primary content.

## The framework

Run these four questions against any homelab diagnosis or
proposed fix before committing to it. Full treatment in
[`references/framework/INDEX.md`](references/framework/INDEX.md);
brief sketch here:

1. **Data layer over surface layer.** What does the layer
   beneath the tool's output actually say? `docker ps` /
   `ufw status` / schema validators all project summaries that
   can disagree with the underlying data. When diagnosis stalls,
   drop one layer.
   ([01-data-vs-surface.md](references/framework/01-data-vs-surface.md))
2. **Ordering, not arg-tuning.** Does the bug live in the call's
   *position*, not its *flags*? Many intermittent failures are
   structural — sync wraps write, read-only wraps mutation —
   and the right fix is reordering, not `--autostash`.
   ([02-ordering-vs-args.md](references/framework/02-ordering-vs-args.md))
3. **Read-only before mutation.** Have I proven the next command
   doesn't write before I run it? Many "diagnostic" commands
   contain a hidden mutation that fires only when state is
   uncertain — exactly when evidence is most valuable.
   ([03-readonly-first.md](references/framework/03-readonly-first.md))
4. **Name the default before answering.** What's the
   plausible-but-wrong default I'm about to reach for? Naming
   it makes principles 1–3 inspectable and lets the user
   confirm or reject the framing.
   ([04-debias-prompt.md](references/framework/04-debias-prompt.md))

The framework fires on any homelab debugging task whether or
not a specific catalog pitfall matches. The pitfalls illustrate
the framework; the framework is what extends the skill to cases
the catalog doesn't cover.

## Mode selection

Pick the mode from the user's framing.

**Retrospective** — past tense + failure framing:
- "what went wrong"
- "post-mortem", "PM", "RCA", "root cause analysis"
- "write up what happened"
- "incident", "outage"
- "the deploy broke X"

**Preventive** — the user has explicitly asked for a review of
a config or change before deploying it. Do not infer preventive
mode from any homelab-adjacent question; require the explicit
ask. The user's project-level CLAUDE.md typically already covers
preventive guidance, and adding it unprompted bloats responses.

If the framing is genuinely ambiguous, ask one short clarifier
and stop:

> Quick check — is this a post-mortem of something that already
> broke, or a preventive review of a config you haven't deployed
> yet?

## Retrospective mode

When in retrospective mode:

1. **Drive the user through the phases** in
   [`references/postmortem-prompts.md`](references/postmortem-prompts.md).
   Don't try to write the PM in one pass; phases keep each step
   focused.
2. **Use [`scripts/gather-logs.sh`](scripts/gather-logs.sh)** to
   pull `journalctl` + `docker logs` + `systemctl status` into
   one bundle. Pass `--max-lines N` to cap output if the
   service is verbose; default cap protects against
   context-poisoning.
3. **Apply the framework during root-cause hypothesis (Phase
   2).** Run the four principles against the hypothesis before
   accepting it. If a catalog pitfall matches, link it; the
   pitfall's "Why LLMs miss this" section is principle 4
   pre-computed for that case.
4. **Fill the [PM template](references/postmortem-template.md)**
   section by section as phases progress; don't draft freeform
   and try to fit it later.
5. **Stop at editable draft.** Tell the user explicitly:
   *"Here's the draft — edit freely. This is the starting
   point, not the finished PM."*

## Preventive mode

When the user has asked for a review:

1. **Apply the framework to the config they showed you.** Walk
   through the four principles in order. Many configs only
   trigger one or two; that's fine. Surface what fires, stay
   silent on what doesn't.
2. **If the symptom maps to a catalog pitfall**, link it and
   summarize the pitfall's named trap. Don't paste the whole
   pitfall content; link to the file.
3. **For ufw-docker-shaped questions**, consider running
   [`scripts/check-ufw-docker.sh`](scripts/check-ufw-docker.sh)
   to confirm a hypothesis with concrete data instead of
   speculating.
4. **Recommend the structural fix shape**, not the arg-tuning
   hack. Principle 2 owns this in detail; pitfall files
   describe the right move per case.

If nothing in the framework or catalog fires on the user's
config, say so and proceed with normal homelab advice. The
framework doesn't have to fire on every interaction.

## Worked examples

Two anonymized PMs in
[`references/examples/`](references/examples/) show the shape:

- [`inbound-fetcher-dirty-tree.md`](references/examples/inbound-fetcher-dirty-tree.md)
  — sync-before-write pitfall as a real PM (illustrates
  principle 2).
- [`qbit-netns-orphan.md`](references/examples/qbit-netns-orphan.md)
  — VPN-sidecar netns orphan as a real PM (illustrates
  principle 1).

Point retrospective-mode users at one of these as a tone-and-
shape reference. Point preventive-mode users at an example
when the underlying pitfall maps to it ("this is what the
failure mode looks like in practice").

## Helpers

| Script | When to use |
|---|---|
| [`scripts/gather-logs.sh`](scripts/gather-logs.sh) | Retrospective mode — pull a bundle of logs for one service. Args: `<service> [--since <duration>] [--max-lines N]`. |
| [`scripts/check-ufw-docker.sh`](scripts/check-ufw-docker.sh) | Preventive or retrospective — diagnose ufw-docker bridge-drop. Args: `[<container>] [<host-ip>] [<port>]`. |

Both scripts are read-only; safe to run during diagnosis. Both
degrade gracefully when a tool is missing.

## Notes for non-trivial requests

- **Stale catalog.** Tooling versions and project conventions
  evolve. If the user reports behavior that contradicts the
  catalog, prefer current observation over the catalog file.
  Flag the staleness as an open item.
- **Catalog contributions.** If an incident reveals a pitfall
  not in the catalog and likely to recur, add it to `## Open`
  in the PM as a candidate for a new entry. Don't write the
  new entry inline; promotion to the catalog happens
  deliberately.
- **Framework extension.** The four principles are a working
  set, not a complete one. If a recurring failure shape
  doesn't fit any of them, surface it; that's a candidate for
  a fifth principle in a future iteration.
