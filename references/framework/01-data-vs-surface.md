# Principle 1 — Data layer over surface layer

Diagnostic tools report a *summary*. The summary is not the
state. Summaries lie in characteristic ways, and the lies are
exactly where homelab debugging gets stuck. The principle: when a
tool's output disagrees with reality, inspect the data the tool
is summarizing — not the tool's verdict.

## The shape

Every diagnostic tool sits one or more layers above the data it
reports on. `docker ps` reads container metadata and renders a
status string. `ufw status` parses iptables rules and projects an
"allow/deny" view. `systemctl status` reads journal lines and
unit state and produces a "running/failed" header. Schema
validators parse a config and report "valid" against a rule set.

When the tool's projection matches reality, you trust it. When
the tool's projection *disagrees with observed behavior*, the
projection is the suspect — not reality.

## How the lying happens

Three patterns recur:

1. **The tool reads a different layer than the one that broke.**
   `docker ps` shows `Up 3 hours` because the parent process is
   alive. The container's network namespace can be empty —
   orphaned by a `network_mode` parent restart — and `docker ps`
   has no view of that. The fix isn't "restart docker"; it's
   inspect `.NetworkSettings.SandboxID` directly and confirm the
   namespace exists.
2. **The tool projects a category that hides the disagreement.**
   `ufw status` says `default deny (incoming)` and lists allow
   rules by port. A container talking from a Docker bridge subnet
   isn't an "incoming" packet from any LAN client's perspective —
   the source IP is on a subnet ufw has no rule for. The
   projection isn't wrong; it just doesn't expose the variable
   that matters.
3. **The tool already transformed the data before reporting.**
   YAML 1.1 parses `off` as boolean `False` before any schema
   validator runs. The schema sees `False` and reports the
   key valid. The source token was a string the user expected
   to be a string. The validator's report is true about its
   input but its input is no longer the user's input.

In all three, the surface is honest about its own narrow view.
The view just doesn't include the failure mode.

## The move

When a diagnosis stalls — the tool says one thing, the system
behaves another — drop one layer:

- Instead of `docker ps`, inspect `docker inspect <ctr>` for
  `SandboxID`, `NetworkMode`, and the container's actual
  `ip -4 addr` from inside its namespace.
- Instead of `ufw status`, run `iptables -L -n -v` and trace the
  packet's source subnet through the chain.
- Instead of `systemctl status`, read raw `journalctl -u <unit>
  -o json` and look at structured fields, not the rendered
  summary.
- Instead of "the schema validates", run
  `python -c 'import yaml; print(repr(yaml.safe_load(open("X"))["key"]))'`
  and inspect the parsed Python type. The repr is the source of
  truth; the schema is a downstream consumer.

The pattern: **find the format the tool is reading from, parse
it yourself, compare against what the tool reported.** Where they
disagree is where the bug lives.

## When this principle fires hardest

- A "successful" command produces no observable effect.
- Two tools report contradictory states for the same resource.
- A symptom returns immediately after a "fix" appears to work.
- A configuration that "looks right" produces wrong behavior at
  runtime.
- A status check passes during startup but the service is
  broken seconds later.

In any of these, surface and data have already diverged. The
question to ask isn't "which tool is right" but "what does the
underlying data say".

## What it costs

Reading the data layer is more work than reading the summary —
that's why summaries exist. Don't skip the summary on every
interaction. Use it as a first cut. The principle applies when
the summary's verdict is *suspect*, not when it's plausible. If
`docker ps` says `Up` and the container is responding to
requests, no namespace inspection is required.

## Worked examples in the catalog

- [ufw-docker bridge drop](../pitfalls/ufw-docker-bridge-drop.md)
  — surface says "rules enforced", data says "your packet's
  source isn't in any rule".
- [`network_mode` netns orphan](../pitfalls/network-mode-netns-orphan.md)
  — surface says container is up, data says the namespace is
  empty.
- [YAML 1.1 boolean trap](../pitfalls/yaml-boolean-trap.md) —
  surface says config is valid, data says the parser already
  converted your value to a different type.

These three pitfalls are the data-vs-surface principle wearing
three different domain hats. Recognizing the shared shape is
how you spot the next instance — in a service or system the
catalog doesn't cover.
