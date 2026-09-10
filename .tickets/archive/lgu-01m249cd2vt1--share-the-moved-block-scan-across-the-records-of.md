---
id: lgu-01m249cd2vt1
title: Share the moved-block scan across the records of one file
status: closed
type: task
priority: 2
mode: afk
created: '2026-09-09T23:52:20.312747857Z'
updated: '2026-09-10T16:04:59.827524799Z'
closed: '2026-09-10T16:04:59.827524799Z'
acceptance:
- title: Stale coverage at 10,000 files and 20 records is measured before and after, three fresh-process trials on the ticket
  done: true
- title: stale --json and coverage --json hash identically before and after on the stale fixtures
  done: true
- title: The ERT tests for a block moved within a file, and for a block with a twin at review time, pass
  done: true
deps:
- lgu-01m249cczbsw
links:
- lgu-01m21qtzrcfq
- lgu-01m249ccrj5h
- lgu-01m249ccvy6a
- lgu-01m249cczbsw
- lgu-01m249cd6dgq
- lgu-01m249cd9v2h
- lgu-01m249cddd06
external_refs:
- git:04d6e70f9622f7d0a3ebaafb30b88d3712992eee
---

## Description

Once anchoring goes through one diff per commit, the stale workload is
bounded by the moved-block fallback in `try-anchor`: every stale record
hashes every window of its file's current text, 1.3 million SHA-256 calls
for 6,000 stale records at 10,000 files and 20 records, 8.5 s of 16.4 s
profiled. The three stale records in one file scan the same 211 windows, and
every window re-trims the lines it shares with its neighbours.

Compute the window hashes of a file once per window length and index them by
hash, trimming each line once; answer `occurrences` from the index. Keep the
cap semantics: a block found twice proves nothing, and the old text is
scanned only when the current text held exactly one match. Measure before
deciding whether the index is worth keeping: the target is stale coverage at
10,000 files and 20 records under 5 s, and the scan is the only cost above
2 s left in the profile.

## Notes

**2026-09-10T16:04:59.516821490Z**

Stale coverage at 10,000 files and 20 records, on the latency experiment's fixture (bench.py build 10000 20, the schema 3 generator at 7762cd6; state stale: the first twenty lines of every fifth file edited). Three fresh bb processes per binary, warm page cache, every core, run serially with nothing else of this session running. Load average 0.3 to 1.1. Babashka 1.13.220, Git 2.47.3, 2026-09-10.

- before, legu at cf4a21d (sha256 9dfbba8f3212...)
- after, legu as committed (sha256 8b451204736f...)

| | trial | wall s | user CPU s | peak RSS MB |
| --- | ---: | ---: | ---: | ---: |
| before | 1 | 7.691 | 7.35 | 421 |
| before | 2 | 8.047 | 7.70 | 432 |
| before | 3 | 7.704 | 7.38 | 439 |
| after | 1 | 4.494 | 4.26 | 394 |
| after | 2 | 4.526 | 4.28 | 394 |
| after | 3 | 4.681 | 4.41 | 433 |

Earlier before windows in the same session gave 7.57 to 7.92 s, 7.65 to 7.79 s and 8.04 to 8.49 s.

Profiled (profile.clj, which inflates both): the moved-block scan went from 8.1 s inclusive of 13.0 s, over 1,306,000 SHA-256 calls, to 2.7 s inclusive of 8.1 s, over 462,000. The three stale records of a file now hash its 211 windows once between them. What is left above 1 s is the resolve loop around it and the sidecar parse at 0.9 s.

The index is worth keeping, but not on the cached file read. A first version hung each file's index off the map read-worktree caches: 4.61 to 4.71 s, and peak RSS 565 to 568 MB, since every stale file's index then lived for the rest of the run. A file's records are anchored one after another, so the committed version keeps one slot, the trimmed lines and per-length indexes of the file asked about last: as fast, at the old peak. The old text's index, built only after a unique match, does not take the slot.

The stale fixture never reaches the old-text check, since its edited records find their block nowhere. A scratch state that does, lines 1-20 of every fifth file cut and pasted at its end (4,000 records found moved, each asking git show for its old text), timed with the two binaries interleaved, one fresh process each, three rounds: before 41.9, 45.3, 40.9 s wall and 16.2, 17.5, 16.3 s user CPU; after 40.2, 50.3, 42.6 s wall and 14.0, 15.3, 14.8 s user CPU. The 4,000 git show calls, 24 s of the profile and 26 to 37 s of system time per run, set the wall time and its spread; the index takes about 1.5 s of CPU off the rest. Peak RSS 427 to 437 MB before, 425 to 436 MB after.

**2026-09-10T16:04:59.623169543Z**

Output hashes, before (cf4a21d) and after (the committed legu). Each is the sha256 of stdout, first 12 hex digits, from bench.py check. The fixtures are built by the schema 3 generator; the stale rows equal the hashes the one-diff-per-commit ticket recorded for the same cells. The moved row is a state added to a scratch copy of bench.py for this ticket: lines 1-20 of every fifth file cut and pasted at its end, so two records of each such file take the moved-block fallback and the old-text check, and a third, straddling the cut, goes stale.

| Files | Records | State | Command | Before | After |
| ---: | ---: | --- | --- | --- | --- |
| 5,000 | 1 | stale | coverage --json | b2266e932b76 | b2266e932b76 |
| 5,000 | 1 | stale | stale --json | dd0925a439ee | dd0925a439ee |
| 5,000 | 20 | stale | coverage --json | fb9b2a9c70be | fb9b2a9c70be |
| 5,000 | 20 | stale | stale --json | f7ddc49bd068 | f7ddc49bd068 |
| 10,000 | 1 | stale | coverage --json | ae38d504a7bf | ae38d504a7bf |
| 10,000 | 1 | stale | stale --json | 02774886e52a | 02774886e52a |
| 10,000 | 20 | stale | coverage --json | 182b3d062844 | 182b3d062844 |
| 10,000 | 20 | stale | stale --json | c4b124889e1a | c4b124889e1a |
| 10,000 | 20 | moved | coverage --json | 2b0dcb19e22f | 2b0dcb19e22f |
| 10,000 | 20 | moved | stale --json | 01125cb1bb08 | 01125cb1bb08 |

Three new ERT tests cover the fallback on a small repository: legu-test-integration-a-region-cut-and-pasted-within-its-file-is-moved, -a-region-found-twice-now-is-stale, and -a-region-with-a-twin-at-review-time-is-stale. Each passes before and after, and each fails against a copy of legu with, in turn, the scan answering nothing, the old-text veto removed, and the cap set to one.

**2026-09-10T16:04:59.827524799Z**

Records that miss the place their diff projects now look their block up in an index of the file's windows, built once per file and window length, where each record hashed every window itself. Stale coverage at 10,000 files and 20 records went from 7.7 s to 4.5 s at the same peak memory. coverage and stale hash identically before and after on the four stale fixtures and on a moved-block one; three new ERT tests pin a region cut and pasted within its file, one found twice, and one with a twin at review time.
