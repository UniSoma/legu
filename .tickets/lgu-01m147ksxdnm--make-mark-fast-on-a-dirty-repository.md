---
id: lgu-01m147ksxdnm
title: Make mark fast on a dirty repository
status: open
type: task
priority: 1
mode: afk
created: '2026-08-28T13:05:43.853705547Z'
updated: '2026-08-28T13:05:43.853705547Z'
acceptance:
- title: '`mark` on a repository with 80 edited files completes in well under a second; record the before and after numbers in a note'
  done: false
- title: Marking after a rename still supersedes the record that moved, leaving no ghost
  done: false
- title: Re-marking the exact range `stale` prints still supersedes the old record
  done: false
- title: The existing whole-file, opaque-file and carried-ticket behaviours are unchanged
  done: false
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
