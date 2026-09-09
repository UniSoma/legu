# Review store encoding experiment

## Recommendation

Keep self-contained EDN records in one sidecar per source file for the 5,000
through 10,000-file target. Use the proposed fixed layout. Treat query latency
as separate work before claiming support for this scale.

At 10,000 files and 20 records per file, grouping by file version saves 37% of
raw bytes and about 4% of the packed Git snapshot. Grouping also halves the
allocated sidecar blocks in this fixture, from 81.92 MB to 40.96 MB. It does
not improve the tested merge outcomes. With a different file version for
every record, grouping increases raw size by 15% and packed size by 5%.

The current CLI misses the 500 ms mark target even with only one record per
file. Reading every sidecar already exceeds that budget at the normal
200,000-record workload, for either encoding. Changing serialization alone
cannot meet the target while retaining that full scan.

No production code or storage contract changed. These results support a
recommendation, not an implemented format or a validated index design.

## Candidates and workloads

- Flat: fixed-layout, self-contained EDN maps, one source-file sidecar.
- Grouped: the same evidence, nested under sidecar-local `(commit, file-hash)`
  groups. Reviewer, timestamp, region boundaries, and content hash stay on each
  record. There are no generated IDs or positional references.
- Both retain full hashes, use deterministic ordering, and keep collection
  delimiters separate from records. Neither stores a redundant source path in
  the encoding comparison.
- Main matrix: 5,000 and 10,000 sidecars, each with 1, 20, or 100 records.
  Records share two file versions, distributed 80/20 where density permits.
- Sensitivity checks: 10,000 sidecars with 20 records each, sharing either one
  file version or none. All records have distinct timestamps within a file;
  four reviewer names recur.
- Regions contain ten lines, with starts seven lines apart, wrapping within
  190 starting positions. This includes overlapping regions.
- Encoding fixtures use deterministic synthetic hashes. They measure storage
  and parsing, not anchoring correctness. Paired merge fixtures were decoded
  and checked for equivalent evidence.

Grouping favors repeated reviews against the same file version. It also changes
source-line ordering into version-first ordering. A record's commit and file
hash can sit outside the context displayed in an ordinary Git diff.

## Storage and decoding

MB means decimal megabytes. Packed size includes `.pack` and `.idx` files after
`git repack -ad` for one committed snapshot containing only sidecars. It excludes
source files, other Git metadata, and historical snapshots. Allocated size sums
sidecar `st_blocks`; it excludes directories.

Decode time includes reading and parsing every sidecar. Grouped decoding also
reconstructs self-contained records. It excludes directory enumeration, process
startup, anchoring, and display. Warm values average the second and third passes
within one Babashka process.

| Files | Records/file | Raw MB flat/grouped | Allocated MB flat/grouped | Packed MB flat/grouped | Warm decode seconds flat/grouped |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 5,000 | 1 | 1.71 / 1.87 | 20.48 / 20.48 | 1.54 / 0.91 | 0.11 / 0.12 |
| 5,000 | 20 | 30.36 / 19.14 | 40.96 / 20.48 | 5.44 / 5.24 | 0.96 / 0.68 |
| 5,000 | 100 | 151.15 / 88.32 | 163.84 / 102.40 | 23.39 / 22.18 | 4.63 / 3.06 |
| 10,000 | 1 | 3.42 / 3.74 | 40.96 / 40.96 | 3.07 / 1.82 | 0.24 / 0.24 |
| 10,000 | 20 | 60.72 / 38.27 | 81.92 / 40.96 | 10.88 / 10.46 | 2.00 / 1.43 |
| 10,000 | 100 | 302.29 / 176.64 | 327.68 / 204.80 | 46.76 / 44.34 | 9.29 / 6.24 |

At one million records, decoding alone exceeds the five-second coverage target
for both candidates. At one record per file, filesystem allocation dominates
raw payload. Grouping increases raw singleton size but packs better in this
Git run; pack results depend on compression and delta-selection heuristics.

### Sensitivity to shared file versions

All rows contain 10,000 files and 20 records per file.

| File versions per file | Raw MB flat/grouped | Packed MB flat/grouped | Warm decode seconds flat/grouped |
| --- | ---: | ---: | ---: |
| One | 60.72 / 36.53 | 10.46 / 9.70 | 2.01 / 1.35 |
| Two, 80/20 | 60.72 / 38.27 | 10.88 / 10.46 | 2.00 / 1.43 |
| Twenty, no sharing | 60.72 / 69.59 | 17.73 / 18.63 | 2.03 / 2.31 |

### Cache and editor limits

A separate 10,000-file, 20-record check flushed each sidecar with `fdatasync`
and requested `POSIX_FADV_DONTNEED` before the first decode. These are cache
hints, not a verified cold disk or a machine-wide cache reset.

| Encoding | First pass after hint, seconds | Subsequent passes, seconds |
| --- | ---: | ---: |
| flat | 3.05 | 2.48, 2.00 |
| grouped | 2.25 | 1.43, 1.68 |

A warm single-sidecar decode at 20 records takes about 0.2 ms flat and 0.14 ms
grouped in Babashka. This does not measure Emacs. Emacs is unavailable on this
machine, so the 100 ms editor-display target remains untested.

## Git patches and merges

These fixtures contain twenty records distributed across two file versions.
Counts below are added/deleted lines from real Git diffs. Superseding at a new
version changes commit, file hash, and timestamp while retaining region content.

| Operation | Flat added/deleted | Grouped added/deleted |
| --- | ---: | ---: |
| Append at an existing file version | 5 / 0 | 3 / 0 |
| Append at a new file version | 5 / 0 | 9 / 0 |
| Re-review at the same file version | 1 / 1 | 1 / 1 |
| Re-review at a new file version | 3 / 3 | 9 / 3 |
| Forget one record | 0 / 5 | 0 / 3 |

Both `git merge-file` and actual two-branch `git merge` gave the same outcomes:

| Concurrent operations in one sidecar | Flat | Grouped |
| --- | --- | --- |
| Edit separated records | Clean | Clean |
| Edit adjacent records | Clean | Clean |
| Competing edits to one record | Conflict | Conflict |
| Append to the same file version at the same insertion point | Conflict | Conflict |
| Append different new file versions at the same insertion point | Conflict | Conflict |
| Forget a record while editing it | Conflict | Conflict |

These fixtures do not prove semantic merge correctness. They do show that
sharing metadata does not remove these insertion conflicts. Fixed-layout
self-contained records keep the version evidence next to each changed record.

## Current CLI latency

The unchanged CLI at commit `40a51ce` ran against actual Git repositories with
220-line source files. Every stored record anchors to one real source commit.
The stale workload edits the first twenty lines in every fifth source file.
Overlapping regions remain in the store.

The CLI fixtures use the flat layout with schema 1 and `:path`, so the existing
reader can consume them. Grouped CLI operations were not implemented or timed.
The results below establish the current access-pattern cost, rather than a
head-to-head comparison of two CLI implementations.

Each cell lists two fresh-process trials in seconds. The OS file cache was not
reset between CLI trials. Each command had a twelve-second limit; `>12` means
it was killed, not that it completed in twelve seconds. The mark adds a region
outside the existing records. Its sidecar is restored between trials.

| Files | Records/file | Source | Mark seconds | Coverage seconds |
| ---: | ---: | --- | ---: | ---: |
| 5,000 | 1 | clean | 1.49, 1.50 | 2.79, 2.75 |
| 5,000 | 1 | stale | >12, >12 | >12, >12 |
| 5,000 | 20 | clean | >12, >12 | >12, >12 |
| 5,000 | 20 | stale | >12, >12 | >12, >12 |
| 10,000 | 1 | clean | 2.91, 2.90 | 5.71, 5.74 |
| 10,000 | 1 | stale | >12, >12 | >12, >12 |
| 10,000 | 20 | clean | >12, >12 | >12, >12 |
| 10,000 | 20 | stale | >12, >12 | >12, >12 |

Code inspection explains why layout alone is insufficient:

- `purge!` visits all sidecars and anchors their review records on each mark.
- `records` loads the whole store for coverage.
- `read-worktree` runs per resolved record; `diff-summary` caches by commit,
  but file reads and per-record anchoring still repeat.
- `resolved-by-path` expands regions into per-line sets.

This is not a profiler attribution. A next experiment should measure batching
file reads and anchoring work, targeted candidate lookup for superseding after
renames, and interval-based coverage. A disposable index is an option, not yet
a demonstrated necessity. Any optimization must preserve rename handling and
supersede semantics.

## Reproduction and limits

The experiment ran on 2026-09-08 UTC in Linux overlayfs, on an Intel i9-13900HX
host with 32 logical CPUs and 32 GB RAM. Tools: Babashka 1.13.220, Git 2.47.3,
and Python 3.13.5. The host was shared, and the cache/branch checks overlapped
part of the storage matrix. Latency figures are indicative, not isolated
performance guarantees. Byte counts and merge outcomes do not depend on that
scheduling overlap.

The source CLI SHA-256 was
`9327ea6b0bd3577beff9434b3d3d0f24b895ad652e9ce9cf6795aad538072713`.

The throwaway source, raw JSON results, and patches are retained on branch
`prototype/review-store-encoding` under `docs/experiments/encoding-prototype/`.
The original scratch directory is `/tmp/legu-encoding-prototype`.

The scripts require an absolute `LEGU` environment variable and operate in
the directory containing the scripts. They replace only their named generated
repositories. In a scratch copy of that directory, the run commands are:

```sh
export LEGU=/absolute/path/to/legu/legu
python3 benchmark.py
python3 branches.py
bb validate.clj patches
python3 report.py
```

The script writes `report.md`. Run the scripts sequentially for cleaner timing.
This experiment does not measure historical Git growth, ticket-heavy stores,
opaque records, alternate storage granularity, index performance, or cold CLI
and editor latency. The 100-record stress case measures encoding and decoding,
not CLI operations. No format migration or backward-compatibility code exists.
