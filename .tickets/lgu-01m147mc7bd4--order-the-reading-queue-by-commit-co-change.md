---
id: lgu-01m147mc7bd4
title: Order the reading queue by commit co-change frequency
status: in_progress
type: feature
priority: 3
mode: afk
created: '2026-08-28T13:06:02.603542986Z'
updated: '2026-09-09T13:31:01.737224240Z'
acceptance:
- title: The ordering uses only git history, with no language knowledge
  done: false
- title: '`next --order cochange` puts files that co-changed with reviewed files first, by descending commit count, then the rest in directory order; `next` without the flag and `next --order dir` keep today''s order'
  done: false
- title: An ERT integration test drives the real binary against a scripted history where the co-change order differs from directory order, and checks both orders and the `--json` shape
  done: false
- title: '`next --order cochange` without git fails naming git as the reason; plain `next` still works without git'
  done: false
- title: The co-change computation is timed on a clone of a multi-year repository with at least ten thousand commits and the repository, commit count, timing, and any history bound are recorded in a note on this ticket
  done: false
- title: README documents both orderings and when each helps, and the CONTEXT.md Queue entry no longer pins directory order
  done: false
---

## Description

`next` orders the queue by directory, and that stays the default: it keeps a
reader inside one part of the tree, and the Emacs package rebuilds that same
order itself from `status --json`.

Add `next --order cochange`, which answers a different question: given what I
have already read, what changes alongside it? Score every file with a gap by
the number of commits in which it changed together with at least one file that
already carries a reviewed line (current or stale). Files with a positive
score come first, highest score first; files with no score follow in directory
order; ties within a score break by directory order. With nothing reviewed
yet, the result equals directory order. `--order dir` names the default
explicitly; any other value is an error, like every unknown option.

The signal is git history only, gathered with one `git log` over the whole
history and no language knowledge. Without git, `--order cochange` fails with
a message saying it needs git, the way `.reviewignore` names git as its
matcher; `next` without the flag keeps working.

The ordering is worthless if `next` stops being instant. Measure `next --order
cochange` on a clone of a repository with several years and at least ten
thousand commits, and record the repository, the commit count, and the timing
in a note on this ticket. If the whole history costs more than one second on
that clone, bound the log to a fixed number of recent commits and record the
bound alongside the measurement.

`--json` carries the same `next` array in the chosen order. The README
documents both orderings and when each helps, and the Queue entry in
CONTEXT.md no longer fixes the ordering to directory order.

## Notes

**2026-09-09T13:31:01.737224240Z**

Timed the co-change ordering on a full clone of https://github.com/redis/redis
(HEAD dce0c76, 13,281 commits, first commit 2009-03-22, last 2026-09-09), with
`legu mark src/server.h` as the only review state.

Best of three runs each, warm cache:

    legu next                    0.85 s
    legu next --order cochange   1.17 s
    git log --name-only -z       0.22 s  (the added git call on its own)

So the ordering adds ~0.33 s on top of a `next` that already costs 0.85 s on a
repository this size. The whole history is read: no bound is applied, because
the cost of reading all 13,281 commits is a third of a second, well inside the
one second the ticket allows the ordering. The 1.17 s total is dominated by
what plain `next` already does — reading every tracked file to count its lines
— which no history bound would touch.

Sanity check on the output: with src/server.h marked, the top of
`next --order cochange` is src/server.c, src/module.c, src/networking.c,
src/db.c, src/config.c — the files that actually move with the main header.
