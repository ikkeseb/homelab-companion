# Post-mortem template

Fill this in after an incident. Aim for 80–150 lines. Keep the tone
declarative and concrete — own the failure without performative
apology. Use real commit hashes, IPs, container names, and log
lines. Show command output including exit codes where they matter.

This is an **incident** template. Planned-change PMs (upgrades,
migrations) have a different shape and aren't covered by v0.1.

---

```yaml
---
title: <one-line description of what broke>
service: <name>            # e.g. qbittorrent, sonarr, gluetun
severity: P3               # P1 outage / P2 major / P3 partial / P4 minor / P5 nuisance
duration: 90m              # symptom onset → confirmed fix
machine: srv-01            # or stack: media-stack
created: YYYY-MM-DD
---
```

# `<title — same as frontmatter>`

## What broke

Symptom-first, concrete. The user-visible failure, the affected
service, the exact error message or log line. Don't editorialize
yet — that's `## Why`.

```
<exact log line, error output, or screenshot description>
```

A few sentences on observable surface behavior:

- What was the user trying to do?
- What happened instead?
- How was the failure first noticed (alert, manual, complaint)?
- What was the blast radius (one user, all users, one service,
  whole stack)?

## Why

Root cause. State the mechanism, not the speculation.

If the bug was conditional or intermittent, add sub-headers:

### Why intermittent

What conditions had to hold for the failure to fire? Why didn't
it fire earlier? What changed in the environment that caused
the conditions to align?

### What conditions had to hold

The minimum set — A, B, and C all had to be true at runtime.
Useful for thinking about whether the same bug exists elsewhere.

If the root cause is one of the catalog pitfalls, link it:

> This is an instance of [scene-RAR vs P2P imports](pitfalls/arr-stack-scene-imports.md).

## Fix

The action that resolved it. Show the diff or the command, not
the prose narrative.

```diff
- write_to_disk(file)
- git("pull --rebase")
+ git("pull --rebase")
+ write_to_disk(file)
```

Or:

```bash
docker restart qbittorrent
```

If the fix landed as a commit, name the hash:

> Fixed in commit `abc1234`.

If the fix is a configuration change, show the before/after.

## Recovery

What was done to restore service after the fix landed. Often
trivial (`docker compose up -d`, queue retry, manual replay) but
worth recording — the recovery path is what happens when this
fires again.

For data corruption or partial-state incidents, include the
specific recovery steps: which files were restored, which
records were re-imported, which manual cleanup was needed.

## Verification

How was the fix confirmed? Show evidence:

- Command output with exit code
- Log line confirming success
- Probe or healthcheck response
- A re-run of the original failing operation

```bash
$ curl -sS http://srv-01:8080/health
{"status":"ok"}
$ echo $?
0
```

"Should be working now" is not verification. Run something that
would have failed before the fix and show that it doesn't fail
now.

## Open

Explicit follow-ups. Link out to where each lesson should be
filed — a catalog pitfall, an ops runbook, an internal doc that
needs updating.

- [ ] Add monitor for the specific failure mode (e.g. external
  HTTP probe of the child container, not just parent
  healthcheck).
- [ ] Update auto-remediation script to handle the case where X.
- [ ] File a pitfall for `<short-shape-name>` if not already in
  the catalog.
- [ ] Decide whether Y should change as a result of this.

Leave items here even if you don't intend to do them this week —
the open list is the record of "we noticed this and decided not
to act yet". An empty `## Open` section is suspicious; a
post-mortem with no follow-ups usually means you stopped
thinking too soon.

---

## Notes on filling this in

**Tone.** Declarative, tight, no performative apology. "We
restarted the parent before the child, which left the child in
an orphaned namespace" — not "Unfortunately, we made the mistake
of restarting incorrectly, and we apologize for the impact."

**Concrete > abstract.** Commit hashes, IPs (RFC1918 if shared
externally), container names, exact log lines, exact commands.
A reader six months later should be able to reproduce the
diagnostic walk from this document alone.

**Length.** 80–150 lines is the working range. Below 80 you've
probably skipped the diagnostic walk; above 150 you're retelling
context that belongs in linked wiki notes instead.

**What not to include.** No timeline-of-meetings, no
shoutouts, no apology paragraph. The post-mortem is a technical
artifact; team-process artifacts go elsewhere.

**Anonymization.** If this PM is going public, swap real
hostnames for `srv-01`-style placeholders, real IPs for
RFC1918 (`192.168.x.x`, `10.x.x.x`), and real customer or
internal service names for generic equivalents. See
[examples/](examples/) for worked anonymization patterns.
