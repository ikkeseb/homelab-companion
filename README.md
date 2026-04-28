# homelab-companion

A Claude Code skill-pack for homelab and self-host operations.
Two complementary modes:

- **Preventive** — surfaces known pitfalls before they bite when
  you're writing or reviewing Docker compose files, ufw rules,
  systemd timers, arr-stack imports, sync workflows, or YAML
  configs. Each pitfall includes a *"Why LLMs miss this"*
  section that names the plausible-but-wrong default answer
  models reach for without context — and tells you how to
  redirect.
- **Retrospective** — structures incident analysis when
  something already broke. Drives a phase-by-phase post-mortem
  through symptom intake, root-cause hypothesis, fix,
  verification, and follow-ups. Outputs an editable Markdown
  draft against a standard template.

Same content base feeds both modes. The catalog of pitfalls is
opinionated — entries land here only when (a) the symptom is
easy to misdiagnose, (b) the root cause is non-obvious, and
(c) a model with no context plausibly gives a wrong answer.

## Who is this for

Anyone running a Docker / Linux homelab who uses Claude Code as
a working assistant. The scope assumes industry-baseline tooling
(Docker, systemd, ufw, gluetun, the arr-stack, Home Assistant,
git) but doesn't insist on any specific topology, NAS, or
distribution.

## Install

Drop the repo into your Claude Code skills directory:

```bash
git clone https://github.com/ikkeseb/homelab-companion.git \
    ~/.claude/skills/homelab-companion
```

Or symlink if you prefer to keep the repo elsewhere:

```bash
ln -s "$(pwd)" ~/.claude/skills/homelab-companion
```

The skill loads automatically on the next Claude Code session.
Confirm it's available with `/skills` — `homelab-companion`
should appear in the list.

## Quickstart

### Preventive mode

Trigger by asking Claude Code about a homelab config you're
about to write or change. Examples:

> Review this compose file before I deploy it.

> I'm setting up gluetun + qBittorrent — anything I should
> watch out for?

> Should I use `network_mode: host` for this CI runner?

The skill loads the matching pitfall(s) from
[`references/pitfalls/INDEX.md`](references/pitfalls/INDEX.md),
flags the AI default trap, and recommends the structural fix.

### Retrospective mode

Trigger by asking for a post-mortem after something broke.
Examples:

> qBittorrent went unreachable after the gluetun restart last
> night — write up what happened.

> We had a Sonarr import failure this morning. Help me
> structure the post-mortem.

> RCA on yesterday's deploy?

The skill drives the phase-by-phase prompts in
[`references/postmortem-prompts.md`](references/postmortem-prompts.md),
optionally pulling logs via
[`scripts/gather-logs.sh`](scripts/gather-logs.sh), and fills
[`references/postmortem-template.md`](references/postmortem-template.md)
section by section. Output is an editable Markdown draft, not a
polished final document.

## What's in v0.1

Six pitfalls covering the highest-yield homelab failure modes:

| Domain | Pitfall |
|---|---|
| Networking / firewall | [ufw drops Docker bridge-to-host traffic](references/pitfalls/ufw-docker-bridge-drop.md) |
| Docker / containers | [`network_mode` parent restart orphans the child's netns](references/pitfalls/network-mode-netns-orphan.md) |
| Media / arr-stack | [Scene-RAR vs flat-MKV release layouts in arr-stack imports](references/pitfalls/arr-stack-scene-imports.md) |
| Git / sync | [Sync before write in shared-write git repos](references/pitfalls/sync-before-write.md) |
| YAML / config | [YAML 1.1 boolean keyword trap](references/pitfalls/yaml-boolean-trap.md) |
| Meta / diagnostic | [Mutative-vs-readonly diagnostics](references/pitfalls/mutative-vs-readonly-diagnostics.md) |

Plus:

- An incident-shape PM template and phase-by-phase prompts.
- Two anonymized worked examples in
  [`references/examples/`](references/examples/) showing the
  shape of a finished post-mortem.
- Two helper scripts:
  - [`scripts/gather-logs.sh`](scripts/gather-logs.sh) —
    bundle `journalctl` + `docker logs` + `systemctl status`
    for one service into one labeled stdout dump.
  - [`scripts/check-ufw-docker.sh`](scripts/check-ufw-docker.sh)
    — diagnose the ufw-docker bridge-drop pitfall against your
    actual ufw rules and Docker bridge subnets.

## Example walkthrough — preventive mode

A user is about to deploy a CI runner that needs to clone from
a Forgejo instance running on the same host:

> User: Setting up a new CI runner in Docker. It needs to ssh
> to the Forgejo bastion on the LAN. Compose looks fine?
> ```yaml
> services:
>   ci-runner:
>     image: forgejo/runner:6
>     restart: unless-stopped
>     environment:
>       FORGEJO_URL: https://forge.lan/
> ```

> Claude Code: This hits the **ufw-docker bridge-drop**
> pitfall. The runner will be on a Docker bridge subnet
> (typically `172.x.x.x`). Your host's ufw default-deny will
> silently drop the runner's SSH attempts to the host's LAN
> IP — the packet's source isn't on the LAN, it's on the
> bridge subnet, and ufw doesn't know about that subnet
> unless you explicitly allow it.
>
> Three fix shapes (see
> [`references/pitfalls/ufw-docker-bridge-drop.md`](references/pitfalls/ufw-docker-bridge-drop.md)):
> ...

## Example walkthrough — retrospective mode

A user reports a failed scheduled job:

> User: My nightly backup script failed at 02:00. Help me
> write this up.

> Claude Code: Quick scope before we write this up:
> - What service or stack broke?
> - When did it start, when fixed?
> - User-visible failure?
> - First-noticed via alert or manual?
>
> Want me to run `scripts/gather-logs.sh backup --since 6h` to
> pull a log bundle?

The user answers. Claude Code fills the PM template section by
section through the phases — symptom intake, root-cause
hypothesis (cross-checked against the pitfall catalog), fix,
recovery, verification, open follow-ups — and hands back an
editable draft.

## Contributing pitfalls

A new pitfall is worth adding when **all three** of these hold:

1. **Symptom is easy to misdiagnose at first glance.** The
   surface presentation points the user away from the actual
   cause.
2. **Root cause is non-obvious.** Requires understanding of an
   underlying mechanism the user wouldn't naturally inspect.
3. **An LLM with no context plausibly gives a wrong answer.**
   This is the differentiator. If models reliably get it right
   without help, the entry adds no signal.

To propose one:

1. Open an issue describing the symptom, root cause, and the
   AI default trap. Include a pointer to a real incident if
   possible.
2. Once the shape is agreed, submit a PR adding
   `references/pitfalls/<slug>.md` following the existing
   template:
   - `## Symptom`
   - `## Root cause` (with `### Diagnosis` sub-section if
     concrete commands help)
   - `## Fix`
   - `## Why LLMs miss this` — original work per entry. The
     plausible-but-wrong default answer, named explicitly, plus
     a redirect prompt that routes models to the correct
     framing.
   - `## See also`
3. Update
   [`references/pitfalls/INDEX.md`](references/pitfalls/INDEX.md)
   with the new row.

The "Why LLMs miss this" section is mandatory and is where the
catalog gets its differentiating value. Don't skip it. Don't
restate the symptom in different words — name the trap.

## Staleness expectations

Tooling versions and conventions change. Each pitfall captures a
real failure mode at the time the entry was written; behavior
may evolve. If a pitfall's diagnostic commands or fix shape no
longer match current behavior, file an issue or PR with the
update.

## License

MIT. See [LICENSE](LICENSE).
