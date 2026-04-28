# Sync before write in shared-write git repos

An auto-push script fails intermittently with `error: cannot pull
with rebase: You have unstaged changes`. The bug is structural:
pull-rebase is being called *after* the working tree was dirtied,
not before. Stash-and-pop doesn't fix it — the bug just moves
from rebase to pop. The right fix is to invert the order, not to
tune git arguments.

## Symptom

A scheduled service that writes to a git-tracked file then
attempts to push fails with:

```
error: cannot pull with rebase: You have unstaged changes.
Please commit or stash them.
```

The script worked for days or weeks before it started failing.
Reruns sometimes succeed (when origin happens to be in sync at
that moment). The error message points at the dirty tree, but
the underlying condition is something else: another writer
pushed since the last run.

Common signal context: a queue file or log file is appended to by
the script, *and* another agent or human is writing to the same
branch from elsewhere — a second host running an auto-sync agent,
a sibling pipeline mutating the same file, manual edits between
runs.

## Root cause

The script's shape is `write → pull-rebase → commit → push`. This
fails when **both** of these hold at runtime:

1. The working tree is dirty (the script just wrote).
2. Origin has commits ahead of local (another writer pushed).

Pull-rebase refuses to operate on a dirty tree when there's
actual rebase work to do. When origin is in sync, pull-rebase
short-circuits with `Already up to date.` and never inspects the
working tree state — which is why the broken shape *appears* to
work for weeks. The bug only manifests in the intersection of
"dirty tree" and "origin ahead", and most of the time origin
isn't ahead.

The bug is **call ordering**, not git arguments. Sync needs to
live one level higher than the writer.

## Fix

Invert the order: pull-rebase **before** working-tree writes.
Sync wraps the writer; the writer doesn't wrap sync.

**Broken shape:**

```python
append_items(queue_path, new_items)   # tree now dirty
git("pull --rebase")                   # refuses if origin is ahead
git("add", queue_path)
git("commit", "-m", "update queue")
git("push")
```

**Corrected shape:**

```python
git("pull --rebase")                   # runs on a clean tree
append_items(queue_path, new_items)    # writer sees post-rebase state
git("add", queue_path)
git("commit", "-m", "update queue")
git("push")
```

For a clean API, split the wrapper into two phases — call sites
become `sync()` then `commit_and_push()`:

```python
class GitPusher:
    def sync(self):
        self._run("pull", "--rebase")

    def commit_and_push(self, paths, message):
        self._run("add", *paths)
        self._run("commit", "-m", message)
        self._run("push")

# in the script:
pusher.sync()
append_items(queue_path, new_items)
pusher.commit_and_push([queue_path], "update queue")
```

The pattern generalizes beyond git — anywhere a scheduled writer
shares state with other writers, "fetch then mutate then publish"
is the right shape, not "mutate then reconcile then publish".

## Why LLMs miss this

The default response to `cannot pull with rebase: You have
unstaged changes` is *"stash, pull, pop"* — or its single-flag
cousin `git pull --rebase --autostash`. Both are local
arg-tuning. Both leave the structural bug in place.

`stash → pull --rebase → stash pop` looks safe but moves the
failure: when the rebase touches the same lines the stashed
write modified (queue files, append-only logs, auto-generated
indexes), `stash pop` produces merge conflicts that need
non-interactive resolution. The script now fails at pop instead
of at rebase. Same root cause, different symptom.

`--autostash` has the same property — it's stash/pop with
implicit timing.

Models reach for arg-level fixes because that's the shape of
most git troubleshooting answers in their training data:
*"have you tried --rebase --autostash?"*, *"add --no-edit"*,
*"use --strategy=ours"*. Structural reorderings — moving a call
one level up in the script — are rare in those answers. The fix
is to change the *shape* of the script, not the args of any
single command.

A useful prompt to deflect the arg-tuning miss: *"don't suggest
git argument changes — what's the call order between the writer
and the sync?"* That redirects the model to the structural
question.

This pitfall sits in a broader **ordering discipline** cluster
with [mutative-vs-readonly diagnostics](mutative-vs-readonly-diagnostics.md).
Both are about ordering: sync wraps write; read-only inspection
wraps mutation. The discipline lives one level above the
operation.

## See also

- [mutative-vs-readonly diagnostics](mutative-vs-readonly-diagnostics.md)
  — sibling pitfall in the ordering-discipline cluster.
- [YAML 1.1 boolean trap](yaml-boolean-trap.md) — different
  domain, but a similar "the surface error is misleading; the
  structural cause lives one layer up" shape.
