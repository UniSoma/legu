---
id: lgu-01m21qtzrcfq
title: Find the next performance changes for large stores
status: closed
type: task
priority: 2
mode: afk
created: '2026-09-09T00:07:14.956466734Z'
updated: '2026-09-09T23:53:40.456694325Z'
closed: '2026-09-09T23:53:40.456694325Z'
acceptance:
- title: Reproduce mark and coverage measurements at 5,000 and 10,000 files with 1 and 20 review records per file. Include clean and stale workloads with overlapping regions; retain 100 records per file as a bounded stress check.
  done: true
- title: Record source revision, machine and tool details, fixture assumptions, operation results, and repeat-run variation. Separate fresh processes, warm caches, and verified cold measurements or cache hints. State any unmeasured cases.
  done: true
- title: Attribute costs to store enumeration and parsing, source reads and hashing, Git subprocesses, anchoring, superseding, and coverage calculations. Record invocation counts or equivalent evidence for repeated work.
  done: true
- title: Compare at least two small experimental changes selected from measured costs, using the same workloads. Record before-and-after latency and verify unchanged review results and supersede behavior on semantic fixtures.
  done: true
- title: Report remaining gaps against mark below 500 ms and coverage below 5 seconds for the normal workload. Keep the editor-display target explicitly unverified unless measured in the editor.
  done: true
- title: Deliver a bounded next implementation plan with real blocking edges, preserved domain invariants, and explicit overlap with the existing mark and editor-query tickets. Explain whether measurements justify a disposable local index; the committed store remains authoritative.
  done: true
- title: Retain reproducible scripts, results, and the verdict as an accessible experiment reference. Leave production behavior and existing tickets unchanged.
  done: true
links:
- lgu-01m249ccrj5h
- lgu-01m249ccvy6a
- lgu-01m249cczbsw
- lgu-01m249cd2vt1
- lgu-01m249cd6dgq
- lgu-01m249cd9v2h
- lgu-01m249cddd06
external_refs:
- git:4b876f27e20bfc0aa75651db537663954f2bd8ed
---

## Description

Identify measured causes of slow marking and coverage. Deliver a bounded implementation plan rather than choosing a local index in advance. This investigation can start with the current encoding and does not depend on the sidecar-format ticket.

Reuse the existing experiment at 5,000 and 10,000 source files. Measure 1 and 20 review records per file, with clean files, stale review records, and overlapping regions. Retain the 100-record case as a stress check. Use declared timeouts where needed; report a timeout as a lower bound, never as a completed duration.

The experiment found that grouping evidence saved about 4% of packed Git size at 10,000 files and 20 records per file. Both mark and coverage exceeded a 12-second limit at that density. The current CLI visits all sidecars during superseding and repeats file reads and anchoring. These observations are hypotheses for profiling, not a completed attribution.

Measure where each command spends time and which work it repeats. Compare small throwaway changes that reduce unnecessary reads, repeated anchoring, or per-line coverage calculations. Preserve review state, rename handling, refusal to follow copies, and supersede semantics. Do not ship a new index or performance redesign in this investigation.

Targets for the normal workload are mark below 500 ms and full coverage below 5 seconds on the measured machine. The separate editor-display target is below 100 ms after editor startup. Do not use CLI parse time as proof of editor latency; keep that target explicitly unverified unless measured.

The results should inform the existing ticket lgu-01m147ksxdnm, Make mark fast on a dirty repository. The existing per-file editor query is lgu-01m147n30cnf. Reference their scopes in the implementation plan without editing, closing, duplicating, or adding blockers to those tickets.

Evidence: throwaway branch prototype/review-store-encoding, commit 2142e22d57db31d871af665916aab59c29df0fcd. It retains the encoding experiment, scripts, raw results, and Git patches.

## Notes

**2026-09-09T20:50:38.211812983Z**

Interim attribution, profiled at HEAD 7a2814b with a babashka wrapper that
counts calls and times each function (exclusive of callees). Fixtures rebuilt
from the encoding experiment's recipe: 220-line files, ten-line records seven
lines apart (overlapping), stale = first twenty lines of every fifth file edited.

coverage, clean, 10,000 files x 20 records: 66 s. `read-worktree` runs 210,000
times (once per record plus once for eligibility), 59 s inclusive; of that the
interpreted byte loop in `binary-bytes?` is ~124 us per call, `lines-of` 13 s,
`sha256-bytes` 5 s. The store is parsed twice (`skipped-paths` and `records`),
4.3 s. Anchoring itself is negligible when the file hash matches.

coverage, stale, 5,000 x 20: 232 s. 20,000 `git show` + 20,000 `git diff
--no-index` = 167 s (one pair per record, not per file). The moved-block
fallback in `try-anchor` hashes every window of both the current and the old
text for each stale record: 1.29 M sha256 calls, 22 s, of which the `hex`
formatting is most of the per-hash cost.

mark, clean, 10,000 x 20: 2.3 s, of which parsing every sidecar is 2.0 s (the
write's contract to name unparseable sidecars); glob 75 ms, stats 65 ms, git
30 ms, process floor 40 ms. Only the target's own sidecar is anchored, as the
closed lgu-01m147ksxdnm left it.

Variants under test: primitives (JVM NUL scan, HexFormat, String.split, skip
the old-text scan unless the block was found once), worktree-cache,
hunks-cache (per commit+path+content), sidecar-once, intervals, and a
parallel parse/read pass; plus one contract-breaking measurement that parses
only candidate sidecars on mark. All but the last pass the CLI suite and the
145-test ERT suite; the last fails exactly the broken-sidecar refusal test.

**2026-09-09T23:53:40.243680789Z**

Findings are in docs/experiments/mark-and-coverage-latency.md (commit
4b876f27e20bfc0aa75651db537663954f2bd8ed); scripts, patches, raw results,
profiles and the ERT log are on branch prototype/mark-coverage-latency at
728137f06d10a0a49c37f62540f1daf02b089710. Production code is untouched.

Against the targets at 10,000 files and 20 records per file, results
unchanged: clean coverage 57 s to 3.9 s (target 5 s, met); stale coverage
>120 s to 11.0 s (2.2x over, the moved-block scan is 8.5 s of it); mark
2.1 s to 0.92 s with the parse on every core (1.8x over, the parse is the
whole gap; 0.20 s with it skipped, which breaks the broken-sidecar
contract). Editor display: unmeasured, stated as such.

Plan: seven linked tickets, lgu-01m249ccrj5h through lgu-01m249cddd06,
with blocking edges in the order the profiles impose. The disposable index
question is answered in the report and in lgu-01m249cd9v2h: only mark's
parse justifies a cache outside the store, only as a parse-verdict cache,
and only if 500 ms at 20 records per file is a hard target.

Two things the report says that a reader of the tables might miss: the
caches alone are slower than baseline on the stale workload at one record
per file (39 s against 28 s at 10,000 files), from subprocess cost that only
partly tracks parent memory, and commit-diff without a pathspec makes mark
1.4 s slower on a dirty tree. Both are in the plan's tickets.

**2026-09-09T23:53:40.456694325Z**

Profiled mark and coverage at 5k and 10k files with 1, 20 and 100 records per file, clean and stale, and attributed the cost: repeated file reads and a double parse on clean trees, two git subprocesses per record and an exhaustive window scan on stale ones, and the full-store parse behind mark. Eight small patches, verified by both test suites and output hashes, take clean coverage from 57 s to 3.9 s, stale coverage from over 120 s to 11 s, and mark from 2.1 s to 0.92 s at 10k files and 20 records. Report on main, scripts and raw results on prototype/mark-coverage-latency, and a seven-ticket plan with blocking edges.
