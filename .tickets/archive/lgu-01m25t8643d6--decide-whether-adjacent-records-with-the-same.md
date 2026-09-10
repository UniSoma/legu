---
id: lgu-01m25t8643d6
title: Decide whether adjacent records with the same evidence coalesce
status: closed
type: task
priority: 3
mode: hitl
created: '2026-09-10T14:06:22.339144419Z'
updated: '2026-09-10T22:28:00.133033696Z'
closed: '2026-09-10T22:28:00.133033696Z'
acceptance:
- title: A note on this ticket records the decision, the scenarios that settled it against ADR-0013, and the ADR it adds or amends if any
  done: true
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

## Notes

**2026-09-10T22:27:59.902729303Z**

Decision: never coalesce. No new ADR; ADR-0004 and ADR-0013 together already settle it.

Scenarios against ADR-0013 and ADR-0004:

- Two marks that abut (1-100, 101-200) at the same commit and file hash. Coalescing to 1-200 keeps ADR-0013 whole on paper but loses precision under ADR-0004: a change at line 150 makes all 200 lines stale where separate records keep 1-100 reviewed. The reviewer who read in passes must re-read twice as much to clear the state.
- A re-mark of 101-200 after that change no longer contains the coalesced record, so the record stays and stale keeps naming 1-200 until the whole span is re-marked. That is the ghost ADR-0013 was written to remove, reintroduced.
- Two marks that overlap, or a mark inside an earlier one: same outcome as abutting, with the extra loss that the overlap's later timestamp overwrites the earlier one or is discarded.
- Same evidence, different timestamps: a merged record carries one timestamp, so one pass's time is lost or invented.
- Forget of one region of a coalesced record: either the whole record goes, dropping coverage the reviewer earned, or the remainder is synthesised with a timestamp nobody produced, which is the option ADR-0013 rejected.

The only variant that keeps every scenario whole is coalescing when a later mark contains both parts, and cmd-mark already does that: purge! retires every contained record and writes one record for the marked span. The gain of the other variants is N-1 resting lines per file read in N passes at one commit, against precision losses in staleness, supersede and forget. Not worth it.

**2026-09-10T22:28:00.133033696Z**

Decided never to coalesce records: the only ADR-0013-safe variant is what mark already does, and merging at mark time trades N-1 sidecar lines for coarser staleness, ghosts on partial re-marks and lossy forget.
