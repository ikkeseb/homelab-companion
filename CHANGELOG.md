# Changelog

All notable changes to homelab-companion are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/);
versioning is informal (no SemVer guarantees pre-1.0).

## [0.2.0] — 2026-05-03

### Added
- **Forensics framework** (`references/framework/`) — four
  reasoning principles promoted from cluster notes to
  first-class content:
  1. Data layer over surface layer
  2. Ordering, not arg-tuning
  3. Read-only before mutation
  4. Name the default before answering
- `references/framework/INDEX.md` — overview and composition
  notes.
- One file per principle with worked examples cross-linked to
  matching pitfalls.
- `--max-lines N` flag on `scripts/gather-logs.sh` (default
  500). Caps `journalctl --lines` and `docker logs --tail` to
  protect Claude's context window from verbose services.
  `--max-lines 0` opts out.

### Changed
- **SKILL.md description narrowed** to retrospective auto-trigger
  only. Preventive mode requires explicit invocation. The old
  "Trigger eagerly" instruction over-fired on routine homelab
  edits and bloated responses; the new framing requires the
  user to opt in for preventive review.
- **SKILL.md restructured** as framework-first: the four
  principles are presented before mode selection. Pitfall
  catalog is now reframed as worked examples of the framework,
  not the primary content.
- **`references/pitfalls/INDEX.md`** gained a "Principles"
  column mapping each pitfall to the framework principles it
  illustrates. The cluster notes were removed (their content
  was promoted to framework principles 1 and 2).
- **`references/postmortem-prompts.md` Phase 2** rewritten to
  walk all four framework principles explicitly during
  root-cause hypothesis, with the catalog as a shortcut when a
  pitfall matches.
- **README** restructured to lead with the framework, document
  the auto-trigger narrowing, and explain why preventive mode
  is opt-in.
- Norwegian-only trigger phrases removed from skill description
  (the skill is public; English is the lingua franca).

### Notes on benchmark
- The v0.1 benchmark (22/22 pass-rate vs 4/22 baseline)
  predates this refactor. Re-benchmarking against v0.2 is open
  work. The framework expansion is expected to help most on
  novel symptoms the catalog doesn't directly cover; the
  catalog cases should perform at least as well as v0.1.

## [0.1.0] — 2026-04

### Added
- Initial release with six pitfalls, two helper scripts
  (`gather-logs.sh`, `check-ufw-docker.sh`), PM template, and
  phase-by-phase prompts.
- Two anonymized worked examples in `references/examples/`.
- v0.1 benchmark: 22/22 pass with skill vs 4/22 baseline
  across 4 evals × 5 runs.
