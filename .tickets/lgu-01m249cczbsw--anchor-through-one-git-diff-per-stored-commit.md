---
id: lgu-01m249cczbsw
title: Anchor through one git diff per stored commit
status: open
type: task
priority: 1
mode: afk
created: '2026-09-09T23:52:20.201028689Z'
updated: '2026-09-09T23:52:20.762003493Z'
acceptance:
- title: Stale coverage at 10,000 files and 20 records completes under 15 s on the experiment's fixture, three fresh-process trials recorded on the ticket
  done: false
- title: mark on the same stale fixture is no slower than before the change, recorded on the ticket
  done: false
- title: coverage, status and stale --json hash identically before and after on the stale fixtures at 5,000 and 10,000 files, 1 and 20 records
  done: false
- title: The ERT integration tests for renames, copies, shifted and moved blocks, and marks after renames pass
  done: false
deps:
- lgu-01m249ccvy6a
links:
- lgu-01m21qtzrcfq
- lgu-01m249ccrj5h
- lgu-01m249ccvy6a
- lgu-01m249cd2vt1
- lgu-01m249cd6dgq
- lgu-01m249cd9v2h
- lgu-01m249cddd06
---

## Description

On the stale workload every record in an edited file runs its own `git show`
and its own `git diff --no-index`: 40,000 subprocesses at 5,000 files and 20
records, 167 s of 232 s. The 20 records of one file share both answers, and
`git diff -U0 <commit> -- <paths>` answers for every file at once.

For a record anchoring at its own path, when git tracks that path, take the
hunks from one `git diff -U0 --no-renames <commit> -- <paths>` per distinct
stored commit, where `<paths>` are the stored paths of the records citing
that commit; parse the output into path to hunks. Any other case keeps the
per-file route: a candidate path from a rename or an added file, an
untracked path, a path git quotes in the diff header, and the old-text scan
of the moved-block fallback, which still needs `git show`, taken lazily.

The prototype, `commit-diff.diff` on branch prototype/mark-coverage-latency,
diffs the whole tree per commit and measured stale coverage at 10,000 files
and 20 records at 11.0 s against more than 120 s, with identical output; it
also made mark 1.4 s slower on that workload because mark paid for the
whole-tree diff. The pathspec is what keeps mark's cost proportional to the
records it anchors.

Hunks from `git diff <commit>` and from `--no-index` over the same bytes are
the same hunks under the default diff configuration; the equivalence check
covers it, and any `diff.*` config that could split them is out of scope.
ADR-0009 stands: a rename is followed, a copy never.
