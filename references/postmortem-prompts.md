# Post-mortem prompts — phase by phase

Decoupled prompts the skill uses to drive a post-mortem
conversation. Each phase has a clear opening question, a
data-collection step, and a hand-off into the next phase.
SKILL.md picks the matching phase based on what the user has
already said and what's already in the draft.

The whole flow targets a fillable
[`postmortem-template.md`](postmortem-template.md). Don't try to
generate a polished PM in one pass — drive it through these
phases, fill the template, hand the editable draft back to the
user.

---

## Phase 1 — Symptom intake

**Goal.** Capture the user-visible failure and the surrounding
facts before reasoning about cause.

**Opening prompt:**

> Quick scope before we write this up:
> - What service or stack broke?
> - When did it start (rough timestamp is fine)?
> - When was it confirmed fixed?
> - What was the user-visible failure — error message, missing
>   data, wrong behavior, full outage?
> - How did you first notice (alert, manual, someone
>   complained)?
>
> Logs and screenshots welcome. If `gather-logs.sh` would help
> here, say so and I'll pull the bundle for you.

**Tool calls available:**
- `scripts/gather-logs.sh <service> --since <duration>` to pull
  `journalctl` + `docker logs` + `systemctl status` into one
  bundle.
- Read any incident-relevant files the user points at.

**Hand-off:** once you have a service name, an approximate
window, and a concrete failure description, fill in the
template's frontmatter (`service`, `duration`, `machine`,
`created`) and `## What broke` section. Then move to Phase 2.

---

## Phase 2 — Root-cause hypothesis

**Goal.** Form a falsifiable hypothesis about why it broke.
Apply the [forensics framework](framework/INDEX.md) to test the
hypothesis before accepting it.

**Opening prompt:**

> Looking at what you've described:
> 1. What's the simplest explanation that fits all the
>    evidence?
> 2. What would have to be true for that explanation to be
>    wrong?
>
> Before we commit to it, I'll run it through the four
> framework principles (data layer, ordering, read-only,
> default-named) and check the catalog for a matching pitfall.

**Framework check.** Run the four principles from
[`framework/INDEX.md`](framework/INDEX.md) against the candidate
hypothesis:

1. **Data layer over surface layer**
   ([01-data-vs-surface.md](framework/01-data-vs-surface.md)) —
   are you trusting a tool's summary (`docker ps`, `ufw status`,
   schema validator) when you should be inspecting what the
   tool is summarizing? `SandboxID`, source IPs, parsed types
   are the data layer; the tool's verdict is the surface.
2. **Ordering, not arg-tuning**
   ([02-ordering-vs-args.md](framework/02-ordering-vs-args.md)) —
   does the bug live in the call's *position* relative to other
   calls? Intermittent failures and "it worked for weeks then
   started failing" are signals. Reorder the calls; don't tune
   the args.
3. **Read-only before mutation**
   ([03-readonly-first.md](framework/03-readonly-first.md)) —
   is the diagnostic command you're about to suggest read-only?
   Do not suggest `force recheck`, `git reset --hard`, `fsck`,
   `REPAIR TABLE`, or any operation whose docs include
   `rebuild`, `repair`, `force`, `reset` — without first naming
   the read-only alternative.
4. **Name the default before answering**
   ([04-debias-prompt.md](framework/04-debias-prompt.md)) —
   what's the plausible-but-wrong default answer for this
   symptom? Name it explicitly before suggesting your
   hypothesis. If your hypothesis *is* the default, run
   principles 1–3 against it harder.

**Catalog check.** Load
[`pitfalls/INDEX.md`](pitfalls/INDEX.md) and scan for matching
domain. If the symptom maps to a catalog entry, load that file —
its "Why LLMs miss this" section is principle 4 pre-computed
for that case, and its "Fix" section names the structural move
the framework would land on. Catalog match is a shortcut; the
framework still applies if no match exists.

**Hand-off:** once you have a hypothesis that survives the
framework checks and the user agrees it's worth testing, fill
the template's `## Why` section. Move to Phase 3.

---

## Phase 3 — Why intermittent / what conditions had to hold

**Goal.** For conditional or intermittent bugs, name the
conditions that had to align.

**Opening prompt:**

> If this only fires sometimes, what conditions had to hold for
> it to fire today? Specifically:
> - What changed in the environment recently?
> - What other writers / consumers / agents touch the same
>   resource?
> - Was there a multi-writer race, a state-dependent code path,
>   a configuration that flipped?
>
> The goal is to write down the minimum set of conditions — A
> AND B AND C — so we know whether the same bug exists
> elsewhere.

**Skip this phase** if the bug is reproducible on demand and
not condition-dependent. Note in the PM that it was deterministic
and move on.

**Hand-off:** fill `### Why intermittent` and `### What
conditions had to hold` sub-sections. Move to Phase 4.

---

## Phase 4 — Fix and recovery

**Goal.** Capture the action that resolved the issue, with
artifacts.

**Opening prompt:**

> Now the action half. For the PM I want:
> - The minimal change that fixed it (diff or command).
> - The recovery steps after the fix landed (compose up, queue
>   retry, manual cleanup).
> - The commit hash if the fix is in code.

**De-bias check.** If the user proposes a fix that's
arg-tuning over a structural bug — e.g. `--autostash` for
[sync-before-write](pitfalls/sync-before-write.md), or "open
the port" for [ufw-docker bridge drop](pitfalls/ufw-docker-bridge-drop.md) —
flag it. Suggest the structural fix and let the user decide
whether to change the PM or accept the local fix.

**Hand-off:** fill `## Fix` and `## Recovery` sections. Move
to Phase 5.

---

## Phase 5 — Verification

**Goal.** Confirm the fix actually works, with evidence.

**Opening prompt:**

> What's the smallest test that would have failed before the
> fix and now passes? I want command output (with exit code) or
> a log line, not "should be working now". If we can re-run the
> original failing operation and capture the output, do that.

**Always require evidence.** "It looks fine" is not
verification. The PM's `## Verification` section needs
something a reader can map back to the original symptom:

- `curl` against the affected endpoint, with response body and
  status code.
- `docker exec <child> ip -4 addr` showing the previously-empty
  namespace now has interfaces.
- `git pull --rebase` succeeding on a dirty tree (or, better,
  the structural fix making the dirty-tree case impossible).
- `python -c 'yaml.safe_load(...)'` showing the parsed type
  matches the source token.

**Hand-off:** fill `## Verification`. Move to Phase 6.

---

## Phase 6 — Open follow-ups

**Goal.** List concrete next steps. An empty `## Open` is a
red flag.

**Opening prompt:**

> Last bit — the follow-up list. Things to think about:
> - What monitor would have caught this earlier? (Often the
>   parent's healthcheck doesn't catch the child's failure —
>   add an external probe of the actual user-facing endpoint.)
> - What auto-remediation needs to handle this case?
> - Does this match a catalog pitfall I should link?
> - Does this match a runbook or internal doc that needs
>   updating?
>
> Even items you don't plan to do this week belong here.

**Catalog feedback.** If the incident exposed a pitfall not
yet in the catalog, name it explicitly:

> The pattern here — `<short shape description>` — isn't in
> the catalog yet. Worth adding as `pitfalls/<slug>.md` if it's
> likely to recur.

**Hand-off:** fill `## Open` and present the full PM draft to
the user for review and edit. The skill's job ends with an
**editable draft**, not a polished final document. Tell the
user explicitly: *"Here's the draft. Edit it freely — this is
the starting point, not the finished PM."*

---

## When the user asks for a PM that already happened

If the user wants to write up an old incident from memory or
from existing logs, run the same phases but skip the
`gather-logs.sh` invocation in Phase 1 (the logs aren't
available anymore, or aren't worth re-fetching). Pull what you
can from existing notes, project logs, or the user's
recollection. Mark unknowns explicitly in the PM rather than
guessing — `(unknown — not in available logs)` is more useful
than a fabricated timestamp.

## When the symptom doesn't match any catalog pitfall

That's fine. The catalog is bounded; real incidents aren't.
Run the phases against the symptom directly. If the root cause
is genuinely novel and likely to recur, flag it in `## Open`
as a candidate for a new catalog entry. Don't force-fit a
pitfall that doesn't apply just because one exists in the
domain.
