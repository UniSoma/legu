---
id: lgu-01m249cddd06
title: Measure the editor-display target in Emacs on the 10,000-file fixture
status: open
type: task
priority: 3
mode: afk
created: '2026-09-09T23:52:20.650832265Z'
updated: '2026-09-10T14:06:32.887993809Z'
acceptance:
- title: Median round-trip time of the regions query from Emacs batch on the 10,000-file, 20-record fixture is recorded on the ticket, clean and stale, ten trials each
  done: false
- title: The share of process start, sidecar parse and anchoring in that time is recorded, from the experiment's profiler
  done: false
deps:
- lgu-01m249cd6dgq
links:
- lgu-01m21qtzrcfq
- lgu-01m249ccrj5h
- lgu-01m249ccvy6a
- lgu-01m249cczbsw
- lgu-01m249cd2vt1
- lgu-01m249cd6dgq
- lgu-01m249cd9v2h
- lgu-01m25t7y4zzf
- lgu-01m25t8643d6
---

## Description

The 100 ms editor-display target has never been measured in Emacs. The
latency experiment measured only the CLI, and says so. `legu regions`, the
per-file query the Emacs package uses (lgu-01m147n30cnf, closed), reads
every sidecar to report an incomplete answer and anchors only the records
that can answer for the file, so its cost on a large store is the parse
pass, which the per-run cache and the parallel pass change.

On the experiment's 10,000-file, 20-record fixture, time `legu regions` from
Emacs in batch: the round trip of `legu-describe-region`'s asynchronous
query from process start to the answer being applied, with the fixture's
store clean and stale, ten trials each, warm cache. Report the medians on
the ticket against the 100 ms target, and what portion is process start,
parse, and anchoring, using the experiment's profiler on the same command
line. Do not use CLI parse time alone as the answer.
