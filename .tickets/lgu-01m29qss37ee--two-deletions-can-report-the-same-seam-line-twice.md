---
id: lgu-01m29qss37ee
title: Two hunks can report the same seam line twice
status: open
type: task
priority: 3
mode: hitl
created: '2026-09-12T02:40:30.823659943Z'
updated: '2026-09-12T03:12:09.656368318Z'
---

## Description

Two hunks inside one region can seam on the same line, and `regions --json`
and `stale --json` then list that line twice.

Repro A, two deletions, on a 150-line file with `mark long.txt:50-100`:
delete lines 90-94 and 96-100. Git reports `@@ -90,5 +89,0 @@` and
`@@ -96,5 +90,0 @@`. The first deletion seams on the line after it (old 95,
now line 90); the second reaches the region end and seams on the line before
it, which is the same line 90.

Repro B, a clipped hunk and a deletion, on the same file with
`mark long.txt:73-150` and a new file of `1-59 / edit 1-5 / line 81`:
hunks `@@ -60,21 +60,5 @@` and `@@ -82,69 +65,0 @@`. The first straddles the
region's start and shrank below the region's offset into it, so it seams
after itself; the second reaches the region's end and seams before itself.
Both land on line 65, and `regions --json` and `stale --json` each list
`65-65` twice.

So neither partner in the collision need be a deletion, and the duplication
is not confined to `regions --json`. Coverage, `stale`'s counts and `next`
merge ranges, so every number is right; what is wrong is the duplicated item,
which `legu-list` counts as two stale regions. `fragments-of` should merge
adjacent or overlapping stale fragments before returning them, or claim the
seam line once.

Found while implementing lgu-01m29hdfw791 (ADR-0018 deletion seam) and
widened by lgu-01m29hdfzjvz (boundary clipping); the review of that phase
found repro B.
