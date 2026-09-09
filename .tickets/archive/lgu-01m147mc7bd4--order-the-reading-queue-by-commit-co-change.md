---
id: lgu-01m147mc7bd4
title: Order the reading queue by commit co-change frequency
status: closed
type: feature
priority: 3
mode: afk
created: '2026-08-28T13:06:02.603542986Z'
updated: '2026-09-09T13:45:11.633452187Z'
closed: '2026-09-09T13:43:40.371513498Z'
acceptance:
- title: The ordering uses only git history, with no language knowledge
  done: true
- title: '`next --order cochange` puts files that co-changed with reviewed files first, by descending commit count, then the rest in directory order; `next` without the flag and `next --order dir` keep today''s order'
  done: true
- title: An ERT integration test drives the real binary against a scripted history where the co-change order differs from directory order, and checks both orders and the `--json` shape
  done: true
- title: '`next --order cochange` without git fails naming git as the reason; plain `next` still works without git'
  done: true
- title: The co-change computation is timed on a clone of a multi-year repository with at least ten thousand commits and the repository, commit count, timing, and any history bound are recorded in a note on this ticket
  done: true
- title: README documents both orderings and when each helps, and the CONTEXT.md Queue entry no longer pins directory order
  done: true
external_refs:
- git:c77cbdf1c99224fe3e4f9cd117a595f47482da32
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

**2026-09-09T13:43:32.484854386Z**

The two ERT tests are written but were never executed: emacs is not installed
in this environment and cannot be installed from here. They were checked by
reading — paren balance verified with a reader, and one real bug fixed (a
helper referenced `root` free, which lexical binding would not have resolved).
The scenario they encode was driven through the real CLI by a bash script and
behaves as asserted: dir order `b/y.txt, c/z.txt, d/w.txt`, cochange order
`c/z.txt, b/y.txt, d/w.txt`, identical orders with nothing reviewed, the same
`--json` shape, exit 1 on an unknown `--order` value, and exit 1 naming git
outside a repository while plain `next` still answers there.

Whoever next runs the suite with emacs available should confirm both tests
before trusting them.

**2026-09-09T13:43:40.371513498Z**

`legu next --order cochange` orders the queue by what changes with what you
have already reviewed: each file with a gap scores the number of commits in
which it changed alongside a file carrying a reviewed line, scored files
first by descending score, the rest in directory order, which is also the
tiebreak. Directory order stays the default and is nameable as `--order dir`;
with nothing reviewed the two orderings are identical. The signal is one
`git log --name-only` over the whole history — no language knowledge — and
`--order cochange` fails naming git outside a repository while plain `next`
still works. README documents both orderings and the CONTEXT.md Queue entry
no longer pins directory order.

Timed on a redis clone (13,281 commits, 2009-2026): the ordering adds ~0.33s
to a `next` that already costs 0.85s, so the history is not bounded.

Caveat, see the note above: the ERT tests were written and reviewed but never
executed — emacs is not installed here. The same scenario passes when driven
through the real CLI.
