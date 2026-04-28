# Mutative-vs-readonly diagnostics

A "diagnostic" check destroys the state you wanted to inspect.
qBittorrent's `force recheck` on a torrent in `missingFiles`
state can overwrite disk bytes. `git reset --hard <commit>`
"to see what it looked like" wipes uncommitted changes.
Filesystem repair tools "rebuild" what they don't understand.
The pattern: operations that present as idempotent checks
contain a hidden mutation that fires only when the check finds
disagreement — exactly the case where you needed evidence
preserved.

This is the most meta of the v0.1 pitfalls. It's a discipline,
not a fact: prove an operation is read-only **before** running
it on uncertain state.

## Symptom

You run a "check" or "diagnostic" command on a system that's
behaving oddly. The command appears to do something. Now the
system behaves differently — sometimes "fixed", sometimes
worse — and you have no way to inspect what was wrong, because
the check overwrote the evidence.

Concrete examples:

- qBit `force recheck` on a torrent in `missingFiles` state
  hashes pieces against the torrent's expected hashes; pieces
  marked "not have" trigger qBit to download the missing
  pieces, **writing them into the existing file at the
  corresponding offsets**. If a different encode of the same
  filename is already on disk, those bytes get overwritten.
- `git reset --hard <commit>` to "see what the tree looked
  like" wipes uncommitted changes in working tree and index.
- `rm -rf "$PATH/"` with `$PATH` silently empty. Glob expands
  to `/`. Mutation fires only because the check (variable set
  or unset) failed silently.
- `REPAIR TABLE`, `fsck`, search-index `reindex` operations.
  Cheap on healthy state, catastrophic when the source of
  truth was already damaged.

## Root cause

Two-part mechanism:

1. The operation is documented as a **check** or **repair**.
   Names suggest read-only or idempotent. `recheck`, `verify`,
   `validate`, `repair`, `fsck`, `reset --hard`. The word
   "force" sometimes attaches but is parsed as "do the check
   harder", not "do the mutation regardless of state".

2. The mutation is **conditional** — it fires only when the
   operation finds disagreement with expected state. On
   healthy state, the operation is genuinely idempotent. The
   trap is exactly when state is uncertain — which is the
   only time you'd run a diagnostic in the first place.

The result: the operation looks safe in every case where
running it didn't matter, and is destructive in every case
where running it did. Diagnostic yield drops to zero at the
moment evidence is most valuable.

## qBit recheck — the worked example

`Force recheck` against a torrent hashes each piece on disk
against the torrent's expected piece hashes:

- Pieces that match → marked `have`. No write.
- Pieces that don't match → marked `not have`, qBit re-requests
  them from peers and **writes the new bytes into the existing
  file at the piece's byte offset**.

Three scenarios where this is destructive:

- **Filename collision.** Sonarr or Radarr replaced the file
  with a different encode but kept the filename. Recheck
  silently overwrites the new encode's bytes with the old
  torrent's bytes.
- **Hardlink to library.** The torrent path is hardlinked to
  the Plex library. Recheck writes affect every inode pointing
  at the data — the library copy gets corrupted along with the
  torrent copy.
- **Multi-file torrent with partial presence.** Recheck
  hashes all "present" files and triggers downloads for
  missing ones. If a present file's bytes drifted (re-encode,
  rename, manual edit) the recheck writes those drifted bytes
  away.

The read-only alternative: parse the `.torrent` metadata
directly from `~/.local/share/qBittorrent/BT_backup/<hash>.torrent`
using a 30-line Python bencode decoder. Extract expected file
list and piece hashes from the `info` dictionary, then `stat`
disk contents in the save path and compare. Everything is
read-only. No qBit state changes, no disk bytes touched.

The cost difference is the entire point. One click for recheck;
30 lines of Python for the read-only path. The ergonomic
gradient pulls hard toward mutation.

## The rule

When state is uncertain, **prove the operation is safe before
you run it**, using only read-only access:

1. Identify whether the operation reads, writes, or both. Read
   the docs; check for words like "rebuild", "repair", "force",
   "reset". Skim the source if available.
2. If it might write, find a read-only substitute: parse data
   formats directly, dump state to temp, use dry-run flags,
   query export APIs.
3. Compare the read-only output against expected state.
4. Only if everything matches expectation, run the mutating
   operation.
5. If anything surprises you in step 3 — *stop*. Don't run the
   mutation to "see what happens". The mutation will not give
   you better evidence.

The ordering is the discipline. This is the same shape as
[sync-before-write](sync-before-write.md): the safety lives one
level **above** the operation, not inside its arguments.

## Why LLMs miss this

Models love suggesting *"force recheck"*, *"git reset --hard"*,
*"rebuild the index"*, *"REPAIR TABLE"*, *"`fsck` it"* as
first-line debug moves. They're high-confidence answers in
training data — clear command names, clear documented purpose,
frequent appearance in StackOverflow answers and tutorials. The
hidden mutation half is rarely highlighted because the answers
selected for training data come from cases where the mutation
*worked* (the user got a clean state and went on with their
day).

Models also don't separate *"tell me state"* from *"compare
and overwrite"*. Both register as "check the state". The
distinction matters most when state is *uncertain* — which is
exactly when the user is asking — and models default to the
shorter, more ergonomic command. The verification habit, when
present at all, is shallow: *"ran the recheck, looks fine
now"* without preserving evidence of the original problem.

There's a related miss around **discernment about what
diagnostic yield even means**. A diagnostic that overwrites
its subject has zero yield by definition: you cannot
distinguish "fixed" from "destroyed" without the original
evidence. Models suggesting recheck or `reset --hard` as a
debugging step rarely flag this. The user accepts the
suggestion, runs the command, the symptom changes, and
neither side knows whether the change was a fix or a cover-up.

A useful prompt to deflect the miss: *"before suggesting any
command that might mutate state, propose a read-only way to
inspect the same state first. If no read-only path exists,
say so explicitly."* That routes the model away from the
ergonomic-but-destructive defaults and forces an explicit
read/write classification.

## See also

- [sync-before-write](sync-before-write.md) — sibling in the
  ordering-discipline cluster. Both are about what wraps what.
- [arr-stack scene-RAR imports](arr-stack-scene-imports.md) —
  the canonical place where qBit `force recheck` is the
  tempting wrong move; this pitfall is the discipline that
  saves you from it.
