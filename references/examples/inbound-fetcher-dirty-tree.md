---
title: inbound-fetcher dirty-tree pull-rebase fix
service: inbound-fetcher-fetch
severity: P3
duration: ~10m (alert → recovery), ~30m (incl. fix + deploy)
machine: srv-01
created: 2026-04-28
---

# inbound-fetcher dirty-tree pull-rebase fix

## What broke

The daily 06:00 local run of `inbound-fetcher-fetch.service`
failed. ntfy fired at 06:00:23 with:

> `inbound-fetcher: FAILED — git failed rc=128`

Direct cause from `journalctl -u inbound-fetcher-fetch.service`:

```
error: cannot pull with rebase: You have unstaged changes.
error: please commit or stash them.
```

The service hadn't failed before that morning. Yesterday's runs
at 19:27 and 19:36 had completed cleanly. No code changes had
shipped overnight on the fetcher itself.

## Why

`GitPusher.push()` ran four steps in this order:

```
pull --rebase → add → commit → push
```

But `main.run_once()` called `append_items(queue_path, new_items)`
**before** calling `pusher.push()`. By the time
`pull --rebase` fired, `.inbox/queue.jsonl` was already modified
in the working tree. With upstream commits to rebase against,
git refused the dirty tree and aborted.

This is an instance of
[sync-before-write](../pitfalls/sync-before-write.md).

### Why intermittent

The bug only manifested when **both** of these held at runtime:

1. `new_items > 0` — the fetcher had something to queue.
   Otherwise `append_items` never ran, and the tree stayed clean.
2. `origin/main` had commits ahead of the srv-01 checkout.
   Otherwise `pull --rebase` short-circuited with "Already up to
   date" regardless of tree state.

Yesterday's runs satisfied (1) but not (2) — origin was in sync
each time, so the pull-rebase short-circuit hid the bug. This
morning, both conditions held: 23 new items queued, and overnight
`origin/main` had moved ~10 commits ahead via PKM auto-sync agent
pushes from two desktop clients plus a queue-truncation commit
(`09968fe`) from the downstream digest pipeline.

The bug would have fired every subsequent day under the same
conditions.

## Fix

Split `GitPusher.push()` into two phases. Caller controls
ordering:

- `sync()` — runs `git pull --rebase` only. Must be called
  **before** any working-tree write. Tree must be clean.
- `commit_and_push(msg)` — runs `add → commit → push` with
  retry. Inline `pull --rebase` between push retries is safe
  because the commit already happened on a clean tree.

`main.run_once()` reordered:

```diff
+ pusher.sync()                            # pre-write sync
  queue_path = repo_path / ".inbox" / "queue.jsonl"
  append_items(queue_path, new_items)
- pusher.push(commit_msg)                  # implicit pull at start
+ pusher.commit_and_push(commit_msg)       # no leading pull
```

This mirrors the same hardening the downstream digest agent
landed three weeks earlier (`9747488 — defensive sync +
rebase-not-merge`). Two independent services hit the same
ordering bug; both fixed it the same way.

Fixed in commit `c1abede`. 49 tests passing, including two new
regression tests:

- `test_commit_and_push_does_not_start_with_pull_rebase` —
  asserts the first git command after `sync()` is `git add`,
  not `git pull --rebase`.
- `test_sync_runs_before_queue_write` — asserts `pusher.sync()`
  fires when `queue.jsonl` is empty, and `commit_and_push()`
  fires only after `queue.jsonl` is populated.

## Recovery

State on srv-01 at incident time: `.inbox/queue.jsonl` had 19
unstaged lines from the failed morning run. The fetcher had
written items locally but never marked them read upstream
(`mark_read NEVER reached` per the early-exit path in
`main.py`).

Discarding the 19 unstaged items was safe — they were never
pushed, the digest never saw them, `state.db` never recorded
them. The next fetcher run would re-pull them from the upstream
unread queue.

```bash
sudo -u inbound-fetcher -H bash -lc "
  cd /srv/inbound-fetcher/internal-knowledge-base && \
  git checkout .inbox/queue.jsonl && \
  GIT_SSH_COMMAND='ssh -i /etc/inbound-fetcher/ssh/id_ed25519 \
    -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new' \
  git pull --rebase
"
```

After the rebase, `queue.jsonl` was 0 bytes (the downstream
digest had truncated it upstream).

## Verification

Manual trigger of `inbound-fetcher-fetch.service` post-deploy:

```
Already up to date.
[main b264d56] inbound-fetcher: 2026-04-28 fetch (23 items)
 1 file changed, 23 insertions(+)
To github.com:acme/internal-knowledge-base.git
   487d0c4..b264d56  main -> main
Deactivated successfully.
```

23 items committed and pushed cleanly (the 19 recovered from the
morning + 4 picked up between the failed run and the manual
trigger). Service exited 0. The next 06:00 local timer firing is
the unattended soak test.

## Open

- [ ] Internal architecture docs describe `git_pusher` as
  "pull-rebase + 3-attempt retry". That sentence is stale —
  the actual API is now `sync()` + `commit_and_push()`. Update
  in the next docs pass.
- [ ] Add monitor: external probe that the next fetcher run
  succeeded, not just that `inbound-fetcher-fetch.service`
  exited 0. The `service` unit succeeded under the original bug
  too, on every day where origin happened to be in sync.
- [ ] Sweep the codebase for other places where the
  write→sync→push shape might exist. The pattern lives one
  level above any specific git operation.
