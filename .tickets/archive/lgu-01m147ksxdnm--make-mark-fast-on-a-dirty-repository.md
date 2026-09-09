---
id: lgu-01m147ksxdnm
title: Make mark fast on a dirty repository
status: closed
type: task
priority: 1
mode: afk
created: '2026-08-28T13:05:43.853705547Z'
updated: '2026-09-09T01:12:52.707798779Z'
closed: '2026-09-09T01:12:52.707798779Z'
acceptance:
- title: '`mark` on a repository with 80 edited files completes in well under a second; record the before and after numbers in a note'
  done: true
- title: Marking after a rename still supersedes the record that moved, leaving no ghost
  done: true
- title: Re-marking the exact range `stale` prints still supersedes the old record
  done: true
- title: The existing whole-file, opaque-file and carried-ticket behaviours are unchanged
  done: true
external_refs:
- git:7ecad789f483fb75cf2e3c5a121a54efdaa3f1a0
---

## Description

`mark` is the verb the user presses most, and on a repository with uncommitted
work it is the slowest thing legu does.

Measured on a 700-file, 133k-line repository: 319ms clean, **2750ms** with 80
files edited. The cost is the supersede pass, which resolves *every* stored
record in the repository — each one a `git show` plus a `git diff --no-index` —
to find the ones a new mark makes obsolete. `note` does the same work in 0.10s
because it filters on the ticket id before resolving anything.

Only records that could possibly be superseded need resolving: those in the
target file's own sidecar, plus sidecars git reports as renames of it. Same
answer, a fraction of the work. No JSON change.

This also shrinks the window in which the Emacs package is painting a mark the
store has not yet accepted — it draws optimistically and reverts on failure,
and that window is currently seconds on a dirty repo.

## Notes

**2026-09-09T01:05:28.291265301Z**

Measured on a synthetic 700-file, 133k-line repository, every file marked
(700 sidecars, one record each), `legu mark` of a fresh range:

| repository state    | before | after |
|---------------------|--------|-------|
| 80 files edited     | 1035ms |  90ms |
| 400 files edited    |  n/m   |  70ms |
| clean               |  270ms |  95ms |

The remaining ~35ms over bb startup is reading every sidecar's EDN, which the
write still does so it can name the ones it cannot parse — the documented
`errors` contract. What it no longer does is *resolve* them: a `git show` plus
a `git diff --no-index` per record, for records that could never have anchored
at the marked file.

Equivalence checked on the same fixture with a rename in the working tree:
`status`, `stale`, `coverage` and `next` `--json` are byte-identical before and
after, and marking the renamed file leaves an identical store (timestamps
aside), old sidecar gone.

**2026-09-09T01:11:30.755276742Z**

The pre-filter decides "could a record stored here anchor somewhere else?" from
`fs/regular-file?`, `fs/readable?` and `git ls-files` — no file contents. The
exact test is `read-worktree`'s own kind, and deriving it that way was tried:
it reads every reviewed file and takes `mark` from 90ms to 260ms on the same
fixture, 3x for one disagreement — a file `fs/readable?` accepts and
`read-all-bytes` then refuses, whose record could claim a newly added file.
Cost of being wrong there is a ghost the next `forget` clears, so the cheap test
stands, with the gap named in the docstring beside `candidate-paths`.

**2026-09-09T01:12:35.251020057Z**

Two deliberate departures from the description, neither a behaviour change:

The filter is not "the target's own sidecar plus sidecars git reports as renames
of it". Rename detection is per record commit, so computing it would pay the
cost being removed here, and a renames-only filter would also miss the second
way `candidate-paths` relocates a record: a stored path that is gone, claiming a
file git calls added. What the filter tests instead is path-independent and
needs no diff — is there a readable file at the stored path, and is git tracking
it? Both relocation routes require one of those to be false, so the answer is
the same and the work is a stat and one `git ls-files`.

The before number in the note above is 1035ms on a 700-record fixture, not the
2750ms the description reports on ~1900 records; that repository is not here to
measure. The shape holds either way — cost tracked how much of the store lived
in dirty files, and now does not track it at all.

**2026-09-09T01:12:52.707798779Z**

`mark` no longer anchors the whole store to find what a mark supersedes, only
the sidecars a record could have moved into: 1035ms to 90ms on a 700-file
repository with 80 files edited, and no longer sensitive to how dirty the tree
is. Same store, same JSON; two ERT integration tests pin the rename cases and
one pins that a write still names an unparseable sidecar.
