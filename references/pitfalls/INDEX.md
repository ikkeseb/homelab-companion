# Pitfalls — index

Pitfalls grouped by domain. Each entry links to its full file and
names the **AI default trap** — the plausible-but-wrong answer most
LLMs give without context. SKILL.md uses this index to load only the
relevant entries per request, not the whole catalog.

| Domain | Pitfall | AI default trap |
|---|---|---|
| Networking / firewall | [ufw-docker bridge drop](ufw-docker-bridge-drop.md) | "Open the port" — without naming the source subnet |
| Docker / containers | [network_mode netns orphan](network-mode-netns-orphan.md) | "Restart the child" — without generalizing to auto-remediation |
| Media / arr-stack | [scene-RAR vs P2P imports](arr-stack-scene-imports.md) | "Check Sonarr settings" — misses structural file-layout difference |
| Git / sync | [sync-before-write in shared repos](sync-before-write.md) | "Stash and pop" — bug just moves from rebase to pop |
| YAML / config | [YAML 1.1 boolean keyword trap](yaml-boolean-trap.md) | "Schema looks right, must be syntax" — parse already failed silently |
| Meta / diagnostic | [mutative-vs-readonly diagnostics](mutative-vs-readonly-diagnostics.md) | "Force recheck / reset --hard / rebuild" — destroys evidence |

## How the index is meant to be used

When a user asks for help in one of these domains, load **the
matching row's pitfall file** (and only that one) before responding.
The point of progressive disclosure is that the catalog can grow
without bloating SKILL.md or every preventive-mode response.

If the user's request crosses two domains, load both files. Loading
the whole catalog is rarely the right move — it costs tokens and
flattens the prioritization that the index encodes.

## Notes — cross-pitfall clusters

Two meta-clusters emerge across the v0.1 set. Worth keeping in mind
when reasoning about a request that doesn't cleanly map to one row.

**Cluster A — surface vs data layer.** Pitfalls #1 (ufw),
#2 (network_mode), and #5 (YAML) all share the same shape: the
surface says one thing, the data layer says another. ufw says
"rules enforced" — but the source IP is the bridge subnet, not the
LAN. `docker ps` says "Up" — but the netns is empty. The schema
"looks valid" — but the parser already converted `off` to `false`
before the schema saw it. The shared move is to read the data layer
directly (`iptables -L -n -v`, `docker inspect ... SandboxID`,
`yq` with explicit type inspection) rather than trust the surface.

**Cluster B — ordering discipline.** Pitfalls #4 (sync-before-write)
and #6 (mutative-vs-readonly) are both about call ordering. Sync
must wrap write, not be wrapped by it. Read-only inspection must
precede any mutating action when state is uncertain. The discipline
lives one level *above* the operation, not inside it. Reordering is
the fix; arg-tuning is not.

These clusters are not pitfalls themselves — they're framings that
help when the literal pitfall list doesn't have an exact match.
