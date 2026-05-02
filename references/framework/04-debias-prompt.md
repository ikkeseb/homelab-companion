# Principle 4 — Name the default before answering

For any homelab symptom, an LLM has a most-likely-next-token
answer that comes pre-loaded from training data. That default
answer is sometimes correct, often plausible-but-wrong, and
occasionally actively destructive. The principle: before
committing to an answer, name what the default would be and
explain why this case is or isn't an instance of it.

This is the metacognitive layer that makes the other three
principles fire reliably. Without it, principles 1–3 are
silent — there's no signal that the current task is the kind
where they apply.

## The shape

LLMs reach defaults from pattern-matching against training
distribution. Many homelab failures sit *just outside* the
training distribution: same symptom shape as a common bug, but
the real cause is a different mechanism. The default answer is
attractive because it answers a related-looking question
fluently. It's wrong because it answers the wrong question.

Naming the default is the move that turns this from invisible
to inspectable. Once named, the default can be checked against
the case at hand.

## How the lying happens

The defaults that hurt are the ones that pattern-match on
**surface phrasing** rather than **causal mechanism**. Three
recurring shapes:

1. **Symptom-keyed defaults.** "Container can't reach host
   port" defaults to *"open the port with `ufw allow 8080`"*.
   That's a rule keyed by **port**, not by **source subnet** —
   wrong for the bridge-drop case where the port is already
   open from the LAN.
2. **Tool-keyed defaults.** "Diagnose qBit state" defaults to
   *"force recheck"*. That's a mutating operation framed as a
   check — wrong for any case where the on-disk file has
   drifted from the torrent's expected bytes.
3. **Error-message-keyed defaults.** "git pull --rebase
   refuses on dirty tree" defaults to *"--autostash"* or
   *"stash, pull, pop"*. That's an arg-fix that moves the
   failure to `stash pop` — wrong for the structural ordering
   bug.

In all three, the default *answers a real question that
looks similar*. The user's actual question has a different
mechanism. The default doesn't fail loudly — it produces an
answer that gets accepted, and the symptom either persists or
moves.

## The move

Before suggesting a fix to a homelab symptom, run a two-step
check:

1. **Name the default.** "The reflexive answer here is X."
   State it explicitly, in one short sentence. "The default
   reach for `cannot pull with rebase: dirty tree` is
   `--autostash`."
2. **Check whether this case is an instance of it.** Run
   principles 1–3 against the named default. Does the data
   layer support it? Is the bug actually in args or in
   ordering? Is the suggested operation read-only or mutating?
   If the default fails any of those, name *why* and propose
   the structural alternative.

If the default passes all the checks, suggest it — defaults
exist because they're often right. The discipline is making
the inspection visible, not avoiding common answers on
principle.

## When this principle fires hardest

- The user reports a symptom phrased in language that closely
  matches a common error message.
- The first answer that comes to mind is a single
  one-liner — a `ufw allow`, a `--force` flag, a
  `restart` command.
- The system or service is one with high training-data
  density (Docker, git, ssh, common databases) — defaults
  are strongest where training is heaviest.
- The user is mid-incident and hasn't yet done the diagnostic
  walk — defaults are most tempting when verification cost
  feels high.

In any of these, the default is a candidate, not a
conclusion. Surface it, then test it.

## What it costs

Naming the default before answering adds a sentence or two to
every response. That's the cost. The benefit is that the user
can see the reasoning — they can disagree with the framing
("no, in our setup that *is* the right move") or confirm
it's the same trap they were about to fall into. Either way
the inspection is shared, not hidden inside the model.

The principle fails when forced. If the answer really is
"the port isn't open, run `ufw allow 8080`", say so —
don't perform a default-naming exercise on a flat
configuration question. Use the principle when the symptom
sits in one of the catalog domains (network, containers,
arr-stack, git-sync, YAML/config) or matches one of the
shapes named above. Use plain answers elsewhere.

## How this principle relates to "Why LLMs miss this"

Every catalog pitfall ends with a **Why LLMs miss this**
section that names the specific default for that pitfall's
symptom. That's principle 4 applied per pitfall —
pre-computed for the catalog cases. When the symptom matches
a pitfall, read its "Why LLMs miss this" section as the
default-name for principle 4.

When the symptom doesn't match a pitfall, run principle 4
yourself: pause, name what the default reach would be,
explain why this case is or isn't an instance of it. The
catalog is a starting library; principle 4 is the move that
extends the library at runtime to cases the catalog doesn't
cover.

## Worked examples in the catalog

- [ufw-docker bridge drop](../pitfalls/ufw-docker-bridge-drop.md)
  § Why LLMs miss this — names the *"open the port"* default.
- [sync-before-write](../pitfalls/sync-before-write.md)
  § Why LLMs miss this — names the *"--autostash"* default.
- [Mutative-vs-readonly diagnostics](../pitfalls/mutative-vs-readonly-diagnostics.md)
  § Why LLMs miss this — names the *"force recheck / reset
  --hard / fsck"* class of defaults.

Reading any pitfall's "Why LLMs miss this" section is a
template for what principle 4 looks like in practice. The
move is the same; the named default changes per case.
