---
name: homelab-companion
description: Use when working on homelab or self-host operations — writing or reviewing Docker compose files, ufw / iptables rules, systemd timers, arr-stack imports, sync workflows, YAML configs, or similar infrastructure — OR after an incident, when asked for a post-mortem, RCA, root-cause analysis, "skriv opp hva som skjedde", or "write up what happened". Surfaces known pitfalls before they bite (preventive mode) and structures incident analysis after they do (retrospective mode). Trigger eagerly even when the user hasn't explicitly asked for AI help — these problem domains are exactly where naive AI advice tends to be wrong, and the catalog short-circuits that failure mode. Norwegian phrasings ("hva gikk galt", "skriv opp", "hvorfor feilet") fire the same as English.
allowed-tools: Read, Write, Edit, Bash
---

# homelab-companion

Two modes: **preventive** (catch known pitfalls before they bite)
and **retrospective** (structure post-mortem analysis after a
failure). Same content base feeds both. The skill is most useful
where naive AI advice tends to be wrong — Docker / ufw interactions,
arr-stack imports, YAML 1.1 traps, ordering bugs in shared-write
git repos, and "diagnostic" commands that destroy evidence.

## Mode selection

Pick the mode from the user's framing **before** anything else.

**Preventive mode** — present or future tense, planning verbs:

- "I'm setting up X"
- "should I…"
- "what's a good way to…"
- "review this compose file"
- "change ufw to…"
- "before I deploy this…"
- "is this safe?"

**Retrospective mode** — past tense + failure framing:

- "what went wrong"
- "post-mortem", "PM", "RCA", "root cause analysis"
- "skriv opp hva som skjedde" / "hvorfor feilet"
- "incident", "outage"
- "the deploy broke X"
- "we had an issue last night"

**Ambiguous** — when both readings fit, ask **one** short
clarifier and stop. Example:

> Quick check — is this a preventive review (you're about to
> deploy and want a sanity pass) or a post-mortem (something
> already broke and you want to write it up)?

Don't try to handle both in the same response. Each mode has a
different opening prompt; mode bleed dilutes the signal.

## Preventive mode

When in preventive mode:

1. **Identify the domain.** Networking, Docker, arr-stack, git/sync,
   YAML/config, or diagnostic-pattern. Read
   [`references/pitfalls/INDEX.md`](references/pitfalls/INDEX.md)
   to see the available domains.
2. **Load only the matching pitfall file(s).** Do not load the
   whole catalog. The index exists precisely so you can stay
   focused. Cross-domain questions may load two files; rarely
   more than two.
3. **Apply the pitfall's "Why LLMs miss this" framing as a
   de-bias prompt** to your own reasoning. Each pitfall names a
   plausible-but-wrong default answer that models reach for
   without context — recognize that pattern in your draft response
   and route around it.
4. **Surface the pitfall to the user.** Brief — name it, name the
   trap, link to the file. Don't paste the whole pitfall content.
   The user can click the link.
5. **Recommend the structural fix shape**, not the arg-tuning
   hack. Pitfall files describe the right move per pitfall.
6. **For ufw-docker-shaped questions**, consider running
   `scripts/check-ufw-docker.sh` to confirm a hypothesis with
   concrete data instead of speculating.

If the user's request doesn't match any pitfall, proceed with
normal homelab advice. The catalog is bounded; not every domain
has a known trap. Don't force-fit.

## Retrospective mode

When in retrospective mode:

1. **Drive the user through the phases** in
   [`references/postmortem-prompts.md`](references/postmortem-prompts.md).
   Don't try to write the PM in one pass — phases exist to keep
   each step focused.
2. **Use [`scripts/gather-logs.sh`](scripts/gather-logs.sh)** to
   pull `journalctl` + `docker logs` + `systemctl status` into
   one bundle. Saves time vs running each command separately and
   gives you a single Read call to reason against.
3. **Cross-reference the pitfall catalog** during the
   root-cause-hypothesis phase. If the symptom matches a catalog
   pitfall, link it — don't restate the cause. The catalog file
   already contains the explanation and the de-bias framing.
4. **Fill the [PM template](references/postmortem-template.md)**
   section by section as the phases progress. Don't draft a
   freeform PM and then try to fit it to the template later.
5. **Stop at editable draft.** The skill's job ends with a
   draft the user can edit, not a polished final document. Tell
   the user explicitly: *"Here's the draft — edit freely. This
   is the starting point, not the finished PM."*
6. **De-bias guards.** Before suggesting any diagnostic command,
   classify it as read-only or mutating per
   [`pitfalls/mutative-vs-readonly-diagnostics.md`](references/pitfalls/mutative-vs-readonly-diagnostics.md).
   Default to read-only inspection. Do not suggest `force
   recheck`, `git reset --hard`, `fsck`, `REPAIR TABLE`, or
   "rebuild the X" without first naming the read-only
   alternative.

## Worked examples

Two anonymized PMs in
[`references/examples/`](references/examples/) show the shape:

- [`inbound-fetcher-dirty-tree.md`](references/examples/inbound-fetcher-dirty-tree.md)
  — sync-before-write pitfall as a real PM.
- [`qbit-netns-orphan.md`](references/examples/qbit-netns-orphan.md)
  — VPN-sidecar netns orphan as a real PM.

When the user is in retrospective mode, point them at one of
these as a tone-and-shape reference. When the user is in
preventive mode and the underlying pitfall maps to one of these,
point them at the example as "this is what the failure mode
looks like in practice."

## Helpers

| Script | When to use |
|---|---|
| [`scripts/gather-logs.sh`](scripts/gather-logs.sh) | Retrospective mode — pull a bundle of logs for one service. Args: `<service> [--since <duration>]`. |
| [`scripts/check-ufw-docker.sh`](scripts/check-ufw-docker.sh) | Preventive or retrospective — diagnose ufw-docker bridge-drop. Args: `[<container>] [<host-ip>] [<port>]`. |

Both scripts are read-only; safe to run during diagnosis. Both
degrade gracefully when a tool is missing (no `journalctl` on
macOS, etc.).

## Mode bleed — what to avoid

- **Preventive contaminating PM.** While writing a PM, don't pivot
  into "and here are five other things to check before your next
  deploy." That's preventive content shoehorned into a PM. If a
  catalog pitfall is relevant, link it; don't write a mini-pitfall
  inline.
- **PM contaminating preventive.** When asked to review a compose
  file, don't open with "let's reconstruct what happened in past
  incidents." The user wants advance warning, not a retrospective.

Each mode has its own opening prompt. Keep separation tight.

## Notes for non-trivial requests

- **Norwegian phrasing.** Norwegian retrospective triggers ("skriv
  opp hva som skjedde", "hva gikk galt", "hvorfor feilet") fire
  retrospective mode the same as English. Reply in the language
  the user wrote in.
- **Stale catalog.** Tooling versions and project conventions
  evolve. If the user reports behavior that contradicts the
  catalog, prefer current observation over the catalog file.
  Flag the staleness as an open item for the user.
- **Catalog contributions.** If an incident reveals a pitfall not
  in the catalog and likely to recur, add it to `## Open` in the
  PM as a candidate for a new entry. Don't write the new entry
  inline — promotion to the catalog happens deliberately.
