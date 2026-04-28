# Curation pass — v0.1

> Working document. Output of build step 2 from
> `the-vault/projects/portfolio/plan-homelab-companion.md`. Drives
> build steps 3 (INDEX.md), 4 (pitfall entries), 5 (PM template),
> 6 (PM prompts), and 7 (anonymized examples). Internal — not
> shipped to end users; refine or delete after v0.1 is locked.

## Source materials read

Mandatory sweep order from the plan, in execution order:

1. `wiki/_index.md` — full read, chunked across two passes
2. `wiki/_bases/` — listed contents (`index.base`, `connectivity.base`,
   `maintenance.base`, `seb.base`); not read in detail because
   `.base` files are dynamic Obsidian views, not human-readable
   content. The flat index already surfaces the same notes.
3. `wiki/log.md` — recent ingest headers (since 2026-04-15) for
   freshness check
4. `wiki/_meta/primer-backlog.md` — Tier 1 primers landed
   2026-04-28 cover ufw-docker, self-hosted CI, arr-stack,
   scene-RAR, sonarr-radarr-import, qBit recheck — all v0.1 or
   v0.2 candidates
5. `projects/homelab/` — listed and read recent PM-style notes
   for template baseline:
   - `2026-04-28 - vault-inbox dirty-tree pull-rebase fix.md` —
     model incident PM
   - `2026-04-27 - forgejo v15 upgrade.md` — model planned-change
     PM
6. `wiki/_moc-homelab.md` — full read; provides the structural
   thinking framework (organize by mode-of-use, not topology)
7. Six v0.1 candidate pitfall notes — full reads
8. Meta-pattern notes for "why LLMs miss this" framing —
   `wiki/trust-the-data-layer-not-the-surface.md` is the load-
   bearing synthesis

## v0.1 pitfall list (6 entries)

Each entry: vault source, symptom, root cause, fix, and the
**"why LLMs miss this"** framing — original work, the
differentiator. Selection criteria from the plan: symptom
misdiagnosable + root cause non-obvious + LLM without context
plausibly wrong.

### 1. ufw drops Docker bridge-to-host traffic

- **Vault:** `[[ufw-docker-bridge-firewall-drop]]`
  (`#domain/networking #source/homelab`)
- **Symptom:** Container can reach external hosts but cannot
  connect to host LAN-IP on a specific port. TCP timeout, no
  ICMP, host logs empty.
- **Root cause:** ufw `default deny (incoming)` drops bridge
  subnet sources (172.x.x.x) that are not in the allow list.
  DROP sends no ICMP unreachable, so the failure is silent.
- **Fixes:** A — `network_mode: host` (least-privilege when
  container has no inbound). B — `ufw allow from 172.18.0.0/16
  to any port 22` (wider blast radius). C — `host.docker.internal`
  via `extra_hosts: - "host.docker.internal:host-gateway"`
  (requires B; not standalone).
- **Why LLMs miss this:** AI defaults to "open the port"
  (`ufw allow 8080`) — rule by port, not by source. The
  container's source isn't on the LAN; it's on the bridge subnet.
  AI also reflexively says "Docker bypasses ufw" as a blanket
  truth, which holds for *publish-to-host* but obscures the
  *bridge-to-host LAN-IP* path that actually hits ufw with a
  non-LAN source. The right move is to identify the source
  subnet *first*, then choose the fix.

### 2. `network_mode` parent restart orphans the child's netns

- **Vault:** `[[network-mode-parent-restart-orphans-child]]`
  (`#domain/ops #domain/networking #source/homelab`)
- **Symptom:** Both containers "Up", parent healthcheck green,
  port mapping intact — but child unreachable from LAN.
  `Connection reset by peer`.
- **Root cause:** `network_mode: container:<parent>` binds the
  child's netns to the parent at container-start time. Parent
  restart orphans the child's netns reference. The child process
  keeps running bound to `0.0.0.0:<port>` in an empty namespace
  (only `lo`).
- **Detection:** `docker inspect <child> --format
  '{{.NetworkSettings.SandboxID}}'` (empty = orphaned).
  `docker exec <child> ip -4 addr` (only `lo` = orphaned).
- **Fix:** `docker restart <child>` after parent reaches
  `Up (healthy)`.
- **Why LLMs miss this:** AI says "restart the child" — works,
  but doesn't proactively warn that *any auto-remediation script
  restarting the parent must also restart the children*. AI
  rarely cites the diagnostic primitives (`SandboxID`,
  `ip addr`). And AI's "parent looks healthy" reading inherits
  the same lie that `docker ps` tells. VPN-sidecar patterns
  (gluetun + qBit, wireguard + arr) are homelab-pandemic on
  this.

### 3. Scene-RAR vs P2P releases on private trackers

- **Vault:** `[[arr-stack-scene-releases]]` +
  `[[unpackerr-for-scene-rar]]` (`#domain/ops #source/homelab`)
- **Symptom:** Sonarr/Radarr report "completed download" but
  no import; queue stuck in `warning` state. No `.mkv` visible
  to import.
- **Root cause:** Scene groups ship `.mkv` packed inside split
  RAR archives (relic of Usenet's article-size limit) — the
  file doesn't exist on disk until `unrar x` runs. P2P groups
  ship flat `.mkv` at the release-folder root. The arr queue
  importer expects flat `.mkv`. Plus: ~2× disk overhead because
  both `.rar` set and extracted `.mkv` must coexist for
  HnR-compliant seeding.
- **Fix:** `golift/unpackerr` sidecar polling the arr APIs,
  running `unrar x` on `warning`-state items. `PATHS_0` must
  match qBit's download path, not Sonarr's library path.
- **Why LLMs miss this:** AI suggests "check Sonarr import
  settings" or "verify the path matches the root folder" —
  generic advice that ignores the structural difference between
  scene-RAR and P2P. Most AI doesn't know about `unpackerr` as
  the standard sidecar pattern, or it'll hallucinate that
  "qBittorrent should auto-extract" (it doesn't). The right
  move requires domain knowledge: *which ecosystem is this
  release from?*

### 4. Sync before write in shared-write git repos

- **Vault:** `[[sync-before-write-shared-repos]]`
  (`#domain/ops #domain/meta #source/homelab`)
- **Symptom:** Auto-push script fails intermittently with
  `error: cannot pull with rebase: You have unstaged changes`.
- **Root cause:** Shape `write → pull-rebase → commit → push`
  fails when **both** upstream has commits **and** working tree
  is dirty. Pull-rebase short-circuits silently when origin is
  in-sync ("Already up to date") regardless of tree state, so
  the bug only manifests when another writer pushed since the
  last run.
- **Fix:** Invert the order — pull-rebase *before* working-tree
  writes. Sync wraps write; write does not wrap sync.
- **Why LLMs miss this:** AI default is "stash → pull-rebase →
  pop" — but pop conflicts when rebase touched the same file.
  Or AI suggests `git pull --autostash`, same problem. The real
  fix is about *call ordering*, not *git command args*. AI
  rarely suggests structural reorderings — it works inside the
  malformed shape. Multi-writer signals (scheduled service +
  sibling agents + downstream consumer mutating the file) make
  this mandatory, not optional.

### 5. YAML 1.1 boolean keyword trap in string-enum config

- **Vault:** `[[yaml-1-1-boolean-keyword-trap]]`
  (`#domain/tooling #source/homelab`)
- **Symptom:** HA Lovelace card "Configuration error", no
  field, no parse-vs-schema distinction. Or GitHub Actions
  `if:` evaluates the wrong way. Or Compose v1 env value
  behaves unexpectedly.
- **Root cause:** YAML 1.1 (PyYAML, libyaml — and therefore
  HA, Ansible, GitHub Actions, Compose v1) silently converts
  unquoted `off`, `no`, `n`, `false`, `on`, `yes`, `y`, `true`
  (and case variants) to bool. Schema expects string enum,
  gets bool, rejects with no useful error.
- **Fix:** Quote string-enum values whose tokens match boolean
  keywords. `mode: 'off'` not `mode: off`.
- **Why LLMs miss this:** AI defaults to `mode: off` because
  it "looks clean". AI rarely volunteers the YAML 1.1
  conversion — even when asked "why does this YAML fail"
  without the parse error in context, AI inspects the schema,
  not the parse. ChatGPT in particular has a habit of "fixing"
  YAML by removing quotes around `'off'` because it "looks
  cleaner". AI lacks discernment that YAML has hidden
  conversions the human eye does not parse.

### 6. Mutative-vs-readonly diagnostics (qBit recheck as worked example)

- **Vault:** `[[mutative-vs-readonly-diagnostics]]` +
  `[[qbit-recheck-semantics]]`
  (`#domain/meta #domain/ops #source/homelab`)
- **Symptom:** "Diagnostic" check destroys the state you wanted
  to inspect. qBit `force recheck` on a `missingFiles` torrent
  overwrites disk bytes. `git reset --hard <commit>` "to see
  what it looked like" wipes uncommitted changes.
- **Root cause:** Operations that present as idempotent checks
  contain hidden mutation that fires only when the check finds
  disagreement. When state was uncertain, you needed read-only
  inspection — but you ran the mutating "check", and the
  evidence is gone.
- **Rule:** Prove the operation is safe with read-only access
  *first*. For qBit: parse `.torrent` metadata via a 30-line
  bencode reader against `BT_backup/` to inspect piece state
  before recheck.
- **Why LLMs miss this:** AI loves suggesting "force recheck",
  `git reset --hard`, `fsck`, "rebuild the index", `REPAIR
  TABLE` as first-line debug moves. AI doesn't separate "tell
  me state" from "compare and overwrite". AI's verification
  habit is shallow — "ran the recheck, looks fine now" —
  without preserving evidence of the original problem. The
  ergonomic gradient points at mutating ops (one click vs
  30-line parser); discipline is noticing that pressure and
  choosing the slower path when state is uncertain.

## v0.2 pipeline (carry-over candidates)

Not in v0.1 to keep scope tight; strong candidates for the
next round:

- `[[pin-lts-not-latest-minor]]` — AI defaults to "latest
  stable", ignoring the LTS axis. Forgejo 14.0.4 → 17-day EOL
  is the canonical worked example.
- `[[arr-custom-formats-minformatscore-trap]]` — silent
  rejection with no error visible. Continues the ARR domain.
- `[[silent-failure-absorbers-as-observation-gaps]]` — `||
  true` + observer reading the side-effect = invisible coupling
  and asymmetric lying. Strong meta-pattern.
- `[[aggregate-equals-single-stream-means-physical-layer]]` —
  AI jumps to TCP tuning when it's actually a loose RJ45.
- `[[obsidian-git-plugin-line-endings]]` — AI says
  ".gitattributes", but isomorphic-git doesn't honor
  `text`/`eol` attributes.
- `[[git-index-exec-bit-windows-trap]]` — AI says `chmod +x`
  without fixing the indexed mode.

## Cross-pitfall connections (INDEX.md grouping)

Two meta-clusters emerge naturally; worth a `## Notes` section
at the bottom of `INDEX.md`:

**Cluster A — surface-vs-data-layer.** Pitfalls #1 (ufw),
#2 (network-mode), #5 (YAML) all share shape: the *surface*
says one thing, the *data layer* says another. ufw "rules
enforced" (but source IP unanticipated). `docker ps` "Up"
(but netns empty). Schema "valid" (but parsed type ≠ source
token type). Anchor: `[[trust-the-data-layer-not-the-surface]]`.

**Cluster B — ordering discipline.** Pitfalls #4
(sync-before-write) and #6 (mutative-vs-readonly) are both
about *call ordering*. Sync must wrap write, not be wrapped
by it. Read-only inspection must precede any mutating action
when state is uncertain. The discipline lives one level *above*
the operation. Anchor:
`[[error-handling-must-live-above-subject]]`.

### Recommended INDEX.md table format (by-domain)

| Domain | Pitfall | "AI default" trap |
|---|---|---|
| Networking / firewall | ufw-docker bridge drop | "Open the port" — without naming the source subnet |
| Docker / containers | network_mode netns orphan | "Restart the child" — without generalizing to auto-remediation |
| Media / arr-stack | scene-RAR vs P2P | "Check Sonarr settings" — misses structural file-layout difference |
| Git / sync | sync-before-write | "Stash and pop" — bug just moves from rebase to pop |
| YAML / config | YAML 1.1 boolean trap | "Schema looks right, must be syntax" — parse already failed silently |
| Meta / diagnostic | mutative-vs-readonly | "Force recheck / reset --hard / rebuild" — destroys evidence |

By-domain is likely the most ergonomic shape for SKILL.md
filtering (the plan flagged this as an Open question). A
by-trigger table can be added later if by-domain doesn't match
how users actually phrase requests.

## PM template style baseline

Extracted from the two PM-style notes in the source-material
sweep. Two distinct shapes, not one:

### Incident PM (v0.1 primary template)

Frontmatter (raw-style minimal in Seb's vault): `title`,
`source`, `created`. For shipped template, add: `service`,
`severity` (P1–P5), `duration`, `machine`/`stack`.

Sections:

- `## What broke` — symptom-first, concrete (logs, error
  message, affected service, exact line)
- `## Why` — root cause; sub-headers for `Why intermittent` /
  `What conditions had to hold` when the bug was conditional
- `## Fix` — the action; commit hash where applicable;
  diff/code snippets for code fixes
- `## Recovery` — what was done to restore service post-fix
- `## Verification` — how the fix was confirmed; show command
  output, exit codes, log lines
- `## Open` — explicit follow-ups with `[[wikilinks]]` to
  where the lesson should be filed

### Planned-change PM (v0.2 candidate)

`## Approach` / `## Pre-flight verification` / `## Cutover` /
`## Post-upgrade verification` / `## Watch-items` /
`## Rollback artifacts` / `## Cross-references`

### Tone (both variants)

Declarative, tight, owns the failure without performative
apology. Concrete commit hashes, IPs, container names, exact
log lines. Code blocks with actual terminal output including
exit codes. Length 80–150 lines for incident, 100–200 for
planned change.

**Recommendation for v0.1:** Ship only the incident template.
Add planned-change in v0.2 — incident shape is what people
actually need when something has gone wrong.

## Example incidents earmarked for anonymization

Each example maps to a v0.1 pitfall. This is a strong
differentiator property the plan didn't explicitly call out
but that falls out naturally: *the same pitfall appears as
preventive advice and as the diagnosed root cause in a
worked PM*.

### 1. vault-inbox dirty-tree pull-rebase fix (2026-04-28)

- **Maps to:** pitfall #4 (sync-before-write)
- **Source:** `projects/homelab/2026-04-28 - vault-inbox
  dirty-tree pull-rebase fix.md`
- **Anonymization:** `vault-inbox` → `inbound-fetcher`,
  `Pi` → `srv-01`, `192.168.0.x` → RFC1918,
  `ikkeseb/the-vault` → `acme/internal-knowledge-base`,
  `Mac/PC` → "two clients", `Obsidian Git plugin` →
  "PKM auto-sync agent"
- **Why strong:** shows the full PM shape (symptom →
  why-intermittent → fix with commit ref → recovery →
  verification → open follow-up) in 80 lines. Model PM.

### 2. gluetun + qBittorrent netns-orphan (2026-04-23)

- **Maps to:** pitfall #2 (network-mode parent restart)
- **Source:** worked example embedded in
  `wiki/network-mode-parent-restart-orphans-child.md`
  § "Worked example — gluetun + qBittorrent (2026-04-23)"
- **Anonymization:** `gluetun` → "VPN sidecar container",
  `qBittorrent` → "torrent client", `NASty` → `nas-01`
- **Why strong:** shows the diagnostic walk — `docker ps`
  lies, port mapping intact, `curl` shows reset,
  `docker exec ... ip -4 addr` shows only `lo`, `SandboxID`
  empty. Needs expansion from wiki bullet form to full PM
  shape (~30 → ~80 lines).

### 3. ufw-docker bridge drop episode

- **Maps to:** pitfall #1 (ufw-docker)
- **Source:** the wiki note has the symptom and diagnostic
  recipe; no separate homelab project log dated for this.
- **Anonymization:** trivial — change container name and
  host IP.
- **Why strong:** simplest to anonymize; ufw-docker is
  probably the pitfall *most* readers will recognize. Worth
  reconstructing as a fictional but realistic worked PM.

**Recommendation:** Ship #1 and #2 in v0.1. #3 is nice-to-have;
add if time allows or defer to v0.2.

## Pending vault content to review

Captured 2026-04-28 in this curation session: the vault is
mid-write on a batch of new and extended notes from a parallel
HA / Tapo D210 / go2rtc work session. None of this is in v0.1
because it landed mid-curation; review after the vault session
settles to decide whether any of it changes the v0.1 shape or
slots into v0.2.

**New atomic notes:**

- `[[go2rtc-tapo-source-bypass]]` (`#type/howto`) —
  workaround architecture, why it works, trade-offs.
- `[[sibling-implementation-bypasses-broken-codepath]]`
  (`#type/pattern #domain/meta`) — generalized pattern with
  go2rtc-tapo as canonical worked example. Distinct from
  `af-packet-bypass` (L2-vs-L7) and from
  `battery-cam-local-api-push-substitute` (push-vs-poll) —
  this is implementation-vs-implementation of the same
  protocol. **Likely v0.2 pitfall candidate** — the meta
  pattern around "AI suggests fixing the broken codepath
  in place; the right move is a sibling implementation"
  is exactly the LLM-miss shape the skill targets.
- `[[apt-upgrade-docker-no-teardown]]` (`#type/reference`) —
  Pi-specific empiri + `+rpt1` Pi Foundation rebuild
  semantics. Possible v0.2 candidate (homelab-routine
  gotcha).

**Larger extensions of existing notes:**

- `[[tapo-d210]]` — alarm_type/events_1 mapping,
  single-tunnel-constraint, motion-no-local-push three-way
  menu, ffmpeg-leak-conclusion go2rtc resolution.
- `[[ha-dashboard-gotchas]]` — `requestFullscreen` blocked
  by HA app-shell, `condition: interaction` debounce
  discipline.
- `[[ha-check-config-before-reload]]` — `ALLOW_EXTRA`
  lesson; HA `go2rtc:` schema only 4 keys, `streams:`
  silently ignored; check warnings field, not just result.
- `[[homelab-security-baseline]]` — header-comments-lie /
  verify-with-`ss`; go2rtc `/api/streams` credential
  exposure as defense-in-depth rationale for loopback bind.
- `[[battery-cam-local-api-push-substitute]]` — D210
  motion-no-local-push as worked example; three-way
  gap-closing menu.
- `[[trust-the-data-layer-not-the-surface]]` —
  header-comments-lie as 8th worked example in Below
  sub-shape.
- `[[independent-layer-verification]]` — ntfy + mobile_app
  fan-out as worked example for parallel-delivery-failsafe.

**Action:** before starting build step 4 (writing pitfall
entries), re-sweep the vault for these notes. If
`sibling-implementation-bypasses-broken-codepath` lands as
expected, evaluate whether to swap it into v0.1 (replacing one
of the current 6) or queue for v0.2. The header-comments-lie
worked example may also strengthen pitfall #1 (ufw) framing
where the analogue is "the rule comment says one thing, the
actual filter does another".
