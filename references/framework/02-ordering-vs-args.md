# Principle 2 — Ordering, not arg-tuning

When a command fails intermittently, the reach for `--retry`,
`--force`, `--autostash`, or `--strategy=ours` is the wrong move
more often than the right one. Many homelab failures live in the
*position* of a call relative to other calls, not in any single
call's arguments. The principle: before tuning flags, ask whether
the bug lives one level above the operation.

## The shape

A script's behavior depends on the order its operations execute,
not just the operations themselves. Many bugs are conditional on
two facts coinciding — and the two facts can only coincide
because the script's *shape* allows them to. Re-tuning either
operation in isolation moves the bug to a different symptom; it
doesn't remove the condition.

The fix is to change the call ordering so the bad coincidence
becomes structurally impossible.

## How the lying happens

Three patterns recur:

1. **Write-then-sync looks fine until origin is ahead.** A
   scheduled script appends to a tracked file, then runs `git
   pull --rebase`. Pull-rebase short-circuits to "Already up to
   date" most of the time and never inspects the dirty tree.
   When another writer pushes between runs, the next pull-rebase
   refuses on the dirty tree. The arg-fix instinct (`--autostash`)
   moves the failure to `stash pop` conflicts. The structural
   fix is `pull-rebase → write → push`, not write-then-reconcile.
2. **Mutation-during-diagnosis destroys the evidence.** Running
   `force recheck`, `git reset --hard`, or `REPAIR TABLE` while
   trying to *understand* an unhealthy state writes over the
   state you needed. The arg-fix instinct (skip the `--force`,
   add `--dry-run`) is right for some tools and wrong for
   others. The structural fix is to prove the operation is
   read-only *before* running it. (Principle 3 owns this case
   in detail.)
3. **Diagnostic-during-mutation hides the failure.** Tests that
   use mocks that drift from production hide the bug at test
   time and surface it at deploy time. The arg-fix instinct is
   to tune the mock. The structural fix is to test against the
   real dependency, where the mock can't drift away from
   production.

In all three, the failing command's docs probably mention a flag
that "fixes" the symptom. The flag fixes the *immediate error
text*. The bad coincidence still happens; the symptom moves.

## The move

When a fix proposal reaches for a flag, ask three questions
before accepting:

1. **What's the call ordering?** Write the script's operations
   in execution order. Where does the failing command sit
   relative to the operation it depends on?
2. **What two facts have to be true together for the failure?**
   If you can name them, you can decide whether reordering
   makes their conjunction impossible.
3. **What's the shape change?** Often the answer is "move call
   X above call Y" or "split call Z into two phases". If the
   answer is "add `--flag`", check whether the same conditions
   could fire under a different surface error.

The pattern: **find the conjunction, change the shape so the
conjunction can't hold.** Args tune behavior inside a shape;
shape changes eliminate the bug class.

## When this principle fires hardest

- A script worked for weeks then started failing.
- Reruns sometimes succeed without changing anything.
- The error message points at the command that failed, but the
  *cause* is something earlier.
- A flag suggested by Stack Overflow "fixes" the symptom but a
  related symptom appears days later.
- Multiple writers/agents touch the same resource (file, branch,
  queue, lock).

In any of these, the shape is suspect. Tune args after the
shape is right; tune shape first.

## What it costs

Reordering calls usually means refactoring a function or
splitting a class. That's heavier than adding a flag — that's
why arg-tuning is the default reach. The cost-benefit is good
when the bug is conditional and the conjunction is structural;
it's bad when the failure really is about a single call's
parameters (a missing `--no-cache`, a wrong timeout). Use the
principle when the failure is intermittent or condition-coupled.
Don't use it when the bug is a flat parameter typo.

## Worked examples in the catalog

- [sync-before-write in shared repos](../pitfalls/sync-before-write.md)
  — write-then-pull-rebase fails when origin is ahead. Args
  (`--autostash`) move the failure; reordering removes the
  conjunction.
- [Mutative-vs-readonly diagnostics](../pitfalls/mutative-vs-readonly-diagnostics.md)
  — sibling: ordering between inspection and mutation.
  Read-only inspection wraps mutation, not the other way.
- [scene-RAR vs P2P imports](../pitfalls/arr-stack-scene-imports.md)
  — `force recheck` is the arg-tuning reach; the structural fix
  is sample-detection during library-import, one call earlier.

These pitfalls share the same shape: the discipline lives one
call above the operation, not inside its arguments.
