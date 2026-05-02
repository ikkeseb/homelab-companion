# Pitfalls — index

Pitfalls are **worked examples of the
[forensics framework](../framework/INDEX.md)** applied to
specific homelab failure modes. Each entry names the **AI
default trap** (principle 4 pre-computed for that case) and the
principles the pitfall illustrates. The framework is the primary
content; this catalog extends it with concrete, recognizable
cases.

| Domain | Pitfall | AI default trap | Principles |
|---|---|---|---|
| Networking / firewall | [ufw-docker bridge drop](ufw-docker-bridge-drop.md) | "Open the port" — without naming the source subnet | 1, 4 |
| Docker / containers | [`network_mode` netns orphan](network-mode-netns-orphan.md) | "Restart the child" — without generalizing to auto-remediation | 1 |
| Media / arr-stack | [scene-RAR vs P2P imports](arr-stack-scene-imports.md) | "Check Sonarr settings" — misses structural file-layout difference | 1, 2 |
| Git / sync | [sync-before-write in shared repos](sync-before-write.md) | "Stash and pop" — bug just moves from rebase to pop | 2, 4 |
| YAML / config | [YAML 1.1 boolean keyword trap](yaml-boolean-trap.md) | "Schema looks right, must be syntax" — parse already failed silently | 1 |
| Meta / diagnostic | [mutative-vs-readonly diagnostics](mutative-vs-readonly-diagnostics.md) | "Force recheck / reset --hard / rebuild" — destroys evidence | 2, 3 |

Principle key: 1 = data-vs-surface, 2 = ordering-vs-args,
3 = readonly-first, 4 = debias-prompt. Full descriptions in
[`../framework/INDEX.md`](../framework/INDEX.md).

## How the index is meant to be used

When a user asks for help in one of these domains, load **the
matching pitfall file** (and only that one) before responding.
Cross-domain questions may load two files. Loading the whole
catalog is rarely the right move — it costs tokens and flattens
the prioritization the index encodes.

The framework files in [`../framework/`](../framework/) take
precedence when no pitfall matches cleanly: the four principles
give a useful answer even on novel symptoms, where the catalog
is silent.

## Notes on the framework's relationship to this index

The two cluster notes in earlier versions of this index —
"surface vs data layer" and "ordering discipline" — have been
promoted to first-class framework principles. Cluster A is now
[principle 1](../framework/01-data-vs-surface.md); Cluster B is
[principle 2](../framework/02-ordering-vs-args.md). Each pitfall
above lists which principles it illustrates; reading the
principle file is the right move when you want the
generalization rather than the specific case.

`mutative-vs-readonly-diagnostics.md` is the special case: it's
both a pitfall (a worked example of the meta-trap) and the
historical seed for [principle 3](../framework/03-readonly-first.md).
The pitfall file goes deeper on the qBit recheck case; the
principle file generalizes the discipline beyond it.
