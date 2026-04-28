# CLAUDE.md — homelab-companion

This file tells Claude Code how to work on this repo. Read it on
every new session.

## What this repo is

A Claude Code **skill-pack** (not a regular app). Two operating
modes — preventive and retrospective — bundled into one skill via
the skill-creator's domain-organization + progressive-disclosure
pattern. The pack ships with `SKILL.md` at the root, content
under `references/`, and helper scripts under `scripts/`.

This is not a Node/Python project. There is no test runner. The
real test is "drop the skill into `~/.claude/skills/` and trigger
it from a fresh Claude Code session". Verification is behavioral.

## Conventions

- **Language.** Code, commits, docs, helper-script output, and
  skill content are in **English**. Conversation in chat may be
  Norwegian.
- **Helper scripts.** Bash for v1. POSIX-friendly where possible.
  No venv, no Node tooling — matches the homelab/self-host
  audience's expected baseline.
- **Pitfall entries** follow the template in
  `references/pitfalls/` (see existing entries once they land).
  The "Why LLMs miss this" field is mandatory and original — that
  is the differentiator.
- **Examples** in `references/examples/` are anonymized real
  incidents. Hostnames replaced with `srv-01`-style placeholders,
  IPs with RFC1918, no customer-adjacent material.
- **Commits.** Conventional-style prefixes (`feat:`, `chore:`,
  `docs:`, `fix:`) when natural; not strictly enforced.

## Vault integration

This repo occasionally writes to `the-vault` (ikkeseb's personal
knowledge vault). Path varies by machine:
`/Users/sebm1/the-vault/` on Mac, `C:/Users/Seb/the-vault/` on
Windows.

**Before writing anything to the vault, read the vault's root
`CLAUDE.md` in full.** It defines folder ownership, frontmatter,
PII rules, and which mode you operate in (you are in a **satellite
session**, §7.2). Re-read at the start of any new session that
expects to write to the vault; it is updated regularly.

PII rules in vault `CLAUDE.md` §6 apply to any notes in this repo
that touch customer work, not just to notes written to the vault.

**Sensitive content — never write to main vault `raw/`.** Captures
there can land in a manual commit at any time and reach GitHub.
Flag to ikkeseb for chat capture into `private/raw/`, or defer
until the next vault session.

## Design rationale

The full plan — mode-selection logic, build steps, validation
criteria, vault source content — lives in the vault, not in this
repo. Read it via the vault path:

```
the-vault/projects/portfolio/plan-homelab-companion.md
```

That file is the source of truth for design decisions. This repo
implements; the vault explains why.
