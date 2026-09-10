---
id: lgu-01m25t8643d6
title: Decide whether adjacent records with the same evidence coalesce
status: open
type: task
priority: 3
mode: hitl
created: '2026-09-10T14:06:22.339144419Z'
updated: '2026-09-10T14:06:32.887993809Z'
acceptance:
- title: A note on this ticket records the decision, the scenarios that settled it against ADR-0013, and the ADR it adds or amends if any
  done: false
deps:
- lgu-01m25t7y4zzf
links:
- lgu-01m25t7y4zzf
- lgu-01m249cd9v2h
- lgu-01m249cd6dgq
- lgu-01m249cddd06
---

## Description

Every mark adds a review record for good, so a file read in ten passes carries
ten lines in its sidecar, and a later re-review of the whole file touches ten
lines of diff. With one record per line (ADR-0015) the count of lines in a
sidecar is the count of lines a pull request shows changing, so fewer records
means less diff noise, which is the metric ADR-0015 chose the format for.

Adjacent or overlapping records by the same reviewer at the same commit and
file hash could coalesce into one record spanning both regions. That is not a
format change: it changes what a mark supersedes and what a ghost is, which
ADR-0013 pins down (a mark supersedes only what it contains, and a record
that reaches outside the mark is left in place). A coalesced record reaches
further than either of its parts, so a later partial re-mark that would have
superseded one part cleanly now leaves a ghost.

Grill this before deciding. Scenarios to settle: two marks that abut, two that
overlap, a mark inside an earlier one, records with the same evidence but
different timestamps, and what a forget of one region does to a coalesced
record. Decide whether coalescing happens at mark time, never, or only when a
mark contains both parts. Reject outright if no scenario keeps ADR-0013 whole.
