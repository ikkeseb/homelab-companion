# homelab-companion

> A Claude Code skill-pack for homelab and self-host operations.
> Surfaces known pitfalls *before* they bite (preventive mode) and
> structures incident analysis *after* they do (retrospective mode).

**Status:** pre-v0.1, under active development. Skeleton only —
content arrives as build steps land. See design rationale in the
project log (vault-private; not in this repo).

## What it is

A Claude skill that activates when you're working on homelab or
self-host infrastructure:

- **Preventive (primary).** When you're writing or reviewing
  Docker compose files, ufw / iptables rules, systemd timers,
  arr-stack imports, sync workflows, or similar config — the
  skill surfaces non-obvious gotchas *before* they bite. Each
  pitfall includes a "why LLMs miss this" framing so the advice
  actively counters AI's typical plausible-but-wrong answer.
- **Retrospective.** When something already broke and you ask
  for a post-mortem / RCA / "write up what happened" — the skill
  scrapes logs, fills a standard PM template, and produces an
  editable Markdown draft.

Same content base feeds both modes.

## Audience

Claude Code users running a homelab or self-host stack. If
`r/selfhosted` and `r/homelab` are part of your reading diet, this
skill is aimed at you.

## Install

This is a Claude Code skill-pack. Install by dropping (or
symlinking) the repo into your skills directory:

```bash
# Symlink (recommended — pulls updates with git)
ln -s "$(pwd)" ~/.claude/skills/homelab-companion

# Or copy
cp -r . ~/.claude/skills/homelab-companion
```

Restart your Claude Code session after install. Trigger the skill
naturally — write a Docker compose file, ask for a post-mortem,
mention ufw rules. The skill activates on context.

## License

MIT. See [LICENSE](LICENSE).
