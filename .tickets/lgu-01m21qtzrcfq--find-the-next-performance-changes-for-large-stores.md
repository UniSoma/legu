---
id: lgu-01m21qtzrcfq
title: Find the next performance changes for large stores
status: open
type: task
priority: 2
mode: afk
created: '2026-09-09T00:07:14.956466734Z'
updated: '2026-09-09T00:07:14.956466734Z'
acceptance:
- title: Reproduce mark and coverage measurements at 5,000 and 10,000 files with 1 and 20 review records per file. Include clean and stale workloads with overlapping regions; retain 100 records per file as a bounded stress check.
  done: false
- title: Record source revision, machine and tool details, fixture assumptions, operation results, and repeat-run variation. Separate fresh processes, warm caches, and verified cold measurements or cache hints. State any unmeasured cases.
  done: false
- title: Attribute costs to store enumeration and parsing, source reads and hashing, Git subprocesses, anchoring, superseding, and coverage calculations. Record invocation counts or equivalent evidence for repeated work.
  done: false
- title: Compare at least two small experimental changes selected from measured costs, using the same workloads. Record before-and-after latency and verify unchanged review results and supersede behavior on semantic fixtures.
  done: false
- title: Report remaining gaps against mark below 500 ms and coverage below 5 seconds for the normal workload. Keep the editor-display target explicitly unverified unless measured in the editor.
  done: false
- title: Deliver a bounded next implementation plan with real blocking edges, preserved domain invariants, and explicit overlap with the existing mark and editor-query tickets. Explain whether measurements justify a disposable local index; the committed store remains authoritative.
  done: false
- title: Retain reproducible scripts, results, and the verdict as an accessible experiment reference. Leave production behavior and existing tickets unchanged.
  done: false
---

## Description

Identify measured causes of slow marking and coverage. Deliver a bounded implementation plan rather than choosing a local index in advance. This investigation can start with the current encoding and does not depend on the sidecar-format ticket.

Reuse the existing experiment at 5,000 and 10,000 source files. Measure 1 and 20 review records per file, with clean files, stale review records, and overlapping regions. Retain the 100-record case as a stress check. Use declared timeouts where needed; report a timeout as a lower bound, never as a completed duration.

The experiment found that grouping evidence saved about 4% of packed Git size at 10,000 files and 20 records per file. Both mark and coverage exceeded a 12-second limit at that density. The current CLI visits all sidecars during superseding and repeats file reads and anchoring. These observations are hypotheses for profiling, not a completed attribution.

Measure where each command spends time and which work it repeats. Compare small throwaway changes that reduce unnecessary reads, repeated anchoring, or per-line coverage calculations. Preserve review state, rename handling, refusal to follow copies, and supersede semantics. Do not ship a new index or performance redesign in this investigation.

Targets for the normal workload are mark below 500 ms and full coverage below 5 seconds on the measured machine. The separate editor-display target is below 100 ms after editor startup. Do not use CLI parse time as proof of editor latency; keep that target explicitly unverified unless measured.

The results should inform the existing ticket lgu-01m147ksxdnm, Make mark fast on a dirty repository. The existing per-file editor query is lgu-01m147n30cnf. Reference their scopes in the implementation plan without editing, closing, duplicating, or adding blockers to those tickets.

Evidence: throwaway branch prototype/review-store-encoding, commit 2142e22d57db31d871af665916aab59c29df0fcd. It retains the encoding experiment, scripts, raw results, and Git patches.
