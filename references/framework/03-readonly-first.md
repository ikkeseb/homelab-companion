# Principle 3 — Read-only before mutation

The most expensive failure mode in homelab debugging isn't the
original bug; it's the diagnostic command that destroyed the
evidence. The principle: when the system's state is uncertain,
prove the next command doesn't write before running it.

## The shape

Many "diagnostic" commands present as idempotent checks but
contain a hidden mutation that fires when the check finds
disagreement — exactly the case where you needed evidence
preserved. The trap is that the operation is genuinely
read-only on healthy state, and genuinely destructive on
unhealthy state. You only run it when you're not sure which
state you're in.

The result: diagnostic yield drops to zero at the moment
evidence is most valuable.

## How the lying happens

The naming convention hides the mutation. Commands documented
as `check`, `verify`, `validate`, `repair`, `fsck`, `recheck`,
`reset --hard` all sit on the boundary between read and
write. The word `force` sometimes attaches and is parsed by
the user as "do the check harder" rather than "do the
mutation regardless of state".

Three concrete patterns:

1. **Conditional mutation on state mismatch.** qBit `force
   recheck` hashes pieces; mismatched pieces trigger
   downloads that overwrite the existing file at the piece
   offset. Healthy torrent: no writes. Drifted torrent:
   silent overwrite of whatever was on disk.
2. **Mutation that "restores expected state".** `git reset
   --hard <commit>` to "see what the tree looked like" wipes
   uncommitted work. `REPAIR TABLE` rebuilds an index from
   data the database doesn't fully understand. Filesystem
   `fsck` rewrites blocks it considers "incorrect". All
   cheap on healthy state, catastrophic when the source of
   truth was already damaged.
3. **Mutation triggered by a silently-failed precondition.**
   `rm -rf "$PREFIX/"` with `$PREFIX` empty expands to
   `/`. The mutation fires only because the precondition
   (variable set) failed silently. Same shape as
   conditional-on-disagreement: the destructive branch
   activates exactly when the safety check it was paired
   with didn't catch the problem.

Models reach for these commands as first-line debug moves
because their training data heavily features cases where the
mutation worked — the user got a clean state and went on with
their day. The cases where the mutation destroyed evidence
don't end up in tutorials.

## The move

When the system's state is uncertain, run the read/write
classification *before* the command:

1. **Read the docs.** Check for `rebuild`, `repair`, `force`,
   `reset`, `recheck`, `verify`. Any of these are flags for
   "this might write".
2. **Find the read-only substitute.** Most operations have one:
   parse the on-disk format directly, dump state via export
   APIs, use `--dry-run` flags, query through a read-only
   replica or backup snapshot, attach with `strace` /
   `lsof` rather than running the operation in earnest.
3. **Compare the read-only output against expectation.** If
   they match, the system is in expected state and you didn't
   need the mutation. If they don't match, you have evidence
   to reason about — *don't* run the mutation to "see what
   happens".
4. **Only mutate when the comparison is clean *and* mutation
   is the actual goal.** Diagnostic-as-mutation is the trap;
   intentional-mutation-after-diagnosis is the discipline.

The pattern: **prove the operation reads what you think it
reads before it writes what it might write.**

## When this principle fires hardest

- A torrent client, package manager, or database is in a
  "broken" state and a "repair" or "rebuild" command exists.
- A version-control operation contains the word `reset`,
  `force`, or `clean`.
- A filesystem tool offers to "fix" inconsistencies.
- A command takes a long time on healthy data — often a sign
  that it's writing as it goes (rebuilding indexes,
  re-hashing blocks, regenerating caches).
- The user is mid-incident and the request is "what should I
  run to see what's wrong" — that's exactly when the
  ergonomic-but-destructive defaults are most tempting.

In any of these, the next command needs explicit
classification before it runs.

## What it costs

Read-only substitutes are usually slower and uglier than the
mutating one-liner. qBit's `force recheck` is one click;
parsing `~/.local/share/qBittorrent/BT_backup/<hash>.torrent`
with a 30-line bencode decoder is more work. That cost
difference is the entire reason the principle is hard to
follow — the ergonomic gradient pulls toward mutation.

The discipline pays for itself the first time you avoid
overwriting library data because you parsed metadata instead
of running recheck. Diagnostic yield is the metric: a
mutation has zero yield because it eliminates the
disagreement that was the evidence.

## Worked examples in the catalog

- [Mutative-vs-readonly diagnostics](../pitfalls/mutative-vs-readonly-diagnostics.md)
  — full treatment with the qBit recheck case worked end to
  end and the read-only substitute spelled out.
- [scene-RAR vs P2P imports](../pitfalls/arr-stack-scene-imports.md)
  — the canonical place where `force recheck` is the
  tempting wrong move during arr-stack debugging.
- [sync-before-write](../pitfalls/sync-before-write.md) —
  sibling in the ordering-discipline cluster (principle 2).
  Both principles say: the discipline lives one call above
  the operation, not inside its arguments.
