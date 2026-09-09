# Mark and coverage latency experiment

## Verdict

Coverage on a clean 10,000-file, 200,000-record store drops from 57 s to
3.9 s with three caches and four constant-factor fixes, none of which changes
a result. Coverage on the stale workload, where a fifth of the files are
edited, drops from more than 120 s to 11 s once anchoring asks git for one
diff per stored commit instead of two subprocesses per record. Both clean
numbers meet the 5 s coverage target; the stale one does not yet.

Mark at 10,000 files and 20 records per file is 2.1 s, and 2.0 s of it is
parsing every sidecar so that a write can name the ones it cannot read.
Parsing on every core brings it to 0.92 s. Nothing measured here brings it
under 500 ms while every sidecar is parsed on every mark: skipping the parse
of sidecars that cannot hold a superseded record gives 0.20 s, and fails the
test that pins the contract. That gap, and only that gap, is where a
disposable local index would earn its place. The committed store stays
authoritative either way.

The editor-display target is unverified. Nothing here ran inside Emacs.

## What was measured

The CLI at commit `7a2814b23c6484543b2932d93bba7e4106951f8a` (SHA-256 of
`legu`: `d8f06893f0a1dcfe326f6b841e5a89d29b4308e746fa8fe9e89151a76383e1e3`),
after the closed lgu-01m147ksxdnm stopped `mark` from anchoring the whole
store. The encoding experiment measured commit `40a51ce`, before that change,
so its mark numbers are not comparable with these.

Fixtures follow the encoding experiment's recipe. Every source file has 220
lines of `file <i> line <j>`. Records are ten lines long with starts seven
lines apart, wrapping within 190 positions, so adjacent records overlap and
at 20 per file every line from 1 to 199 is under several records. Every
record cites the real commit, file hash and normalized content hash of its
region, so anchoring is real. The stale workload appends ` edited` to the
first twenty lines of every fifth file, which makes the records over those
lines stale and every other record in those files re-anchor through a diff.
The clean workload is the committed tree. Fixtures at 100 records per file
are the bounded stress check.

Operations: `coverage --json`; `mark` of lines 201-210 of the first file,
outside every stored record; and `mark` of lines 1-60 of the same file, which
supersedes records. The target sidecar is restored between trials.

Every timing is a fresh `bb` process with a warm page cache, three trials for
the baseline and the combined variants and two for the single-change
variants, 120 s limit. A cell reading `>120` was killed at the limit and is
a lower bound. Tables show the median with the range in parentheses, in
seconds. The process floor, `legu --version`, is 42 to 51 ms.

Attribution comes from a wrapper that loads the script, wraps 50 of its
functions with call counters and inclusive and exclusive timers, and runs the
command line. The wrapper adds a few microseconds per call, so a profiled run
is 2 to 15% slower than the plain one; profiles report both.

Machine and tools: Intel i9-13900HX, 32 logical CPUs, 31 GB RAM, Linux
7.0.0-31-generic in an overlayfs container, Babashka 1.13.220, Git 2.47.3,
Python 3.13.5, Emacs 30.1, 2026-09-09 UTC. The timing matrix ran serially
with nothing else on the host; the profiles and equivalence checks ran in
one serial chain afterwards.

## Where the time goes

Profiles of the unchanged CLI. Times are exclusive of callees.

Coverage, clean, 10,000 files, 20 records per file: 66 s.

| Function | Calls | Exclusive |
| --- | ---: | ---: |
| `read-worktree` | 210,000 | 41.3 s |
| `lines-of` | 210,000 | 12.7 s |
| `sha256-bytes` | 210,000 | 5.5 s |
| `parse-sidecar` | 20,000 | 4.3 s |
| everything else | | 2.5 s |

Every source file is read, hashed and split 21 times: once per record in
`resolve-region`, once more in `eligible-files`. Every sidecar is parsed
twice, in `skipped-paths` and again in `records`. Of `read-worktree`'s own
time, the interpreted loop in `binary-bytes?` is about 124 µs per call, 26 s
of the 41 s. Anchoring is negligible on a clean tree: the file hash matches
and `try-anchor` returns at once.

Coverage, stale, 5,000 files, 20 records per file: 232 s.

| Function | Calls | Exclusive |
| --- | ---: | ---: |
| `diff-hunks` | 20,000 | 84.4 s |
| `read-at-commit` | 20,000 | 83.0 s |
| `read-worktree` | 105,000 | 22.5 s |
| `sha256` | 1,286,000 | 17.5 s |
| `lines-of` | 108,000 | 7.8 s |
| `norm-hash` | 1,286,000 | 4.4 s |
| `parse-sidecar` | 10,000 | 2.7 s |
| `occurrences` | 6,000 | 1.6 s |

Each of the 20,000 records in an edited file runs its own `git show` and its
own `git diff --no-index`, although the 20 records in one file share both
answers: 40,000 subprocesses at about 4 ms each. The 3,000 stale records
then take the moved-block fallback, which hashes every ten-line window of
the current text and of the old text: 1.29 million SHA-256 calls, most of
their cost in the per-byte `format` behind `hex`. The old-text scan only
matters when the current text held exactly one match, which never happens
in this workload.

Mark, clean, 10,000 files, 20 records per file: 2.3 s. `parse-sidecar` is
2.0 s over 10,002 calls, `stored-paths` 75 ms, `may-have-moved?` 65 ms for
10,000 stats, four git calls 30 ms. The parse is the write's contract: it
names every sidecar it cannot read. The purge anchors only the target's own
sidecar, as lgu-01m147ksxdnm left it.

## The changes tried

Each is a text substitution on a copy of the script, generated by
`make_variants.py` and kept as a patch; the largest is 74 diff lines.

- **primitives**: `binary-bytes?` finds a NUL with `String.indexOf`; `hex`
  uses `java.util.HexFormat`; `lines-of` uses `String.split`; `try-anchor`
  scans the old text only when the current text held exactly one match.
  Micro-benchmarks: binary check 124 µs to 1 µs, line split 78 µs to
  27 µs; a hash is 12 µs in the baseline profile and 4 µs after.
- **worktree-cache**: `read-worktree` remembered per path for the run.
- **hunks-cache**: `git show` remembered per commit and path, `git diff
  --no-index` per commit, path and current file hash.
- **sidecar-once**: each sidecar parsed once per run, the store enumerated
  once, both forgotten on a write to that sidecar.
- **intervals**: coverage counted over merged line intervals instead of
  per-line sets; the sets `status` and `next` print are built from the
  merged intervals afterwards.
- **parallel**: `pmap` over the parse pass and the working-tree read pass,
  filling the two caches above.
- **commit-diff**: one `git diff -U0 <commit>` per distinct stored commit,
  parsed into path to hunks, for records anchoring at their own tracked
  path. Other records, and paths git quotes in the diff header, keep the
  per-file route. Applies on top of hunks-cache.
- **mark-candidates-only**: not shippable. The purge parses only the
  sidecars that can hold a superseded record. It measures the parse
  contract's price.

`combined` is the first five; `combined-parallel` adds parallel;
`combined-commit-diff` and `combined-parallel-commit-diff` add commit-diff.

### Results and supersede behaviour are unchanged

Every variant except mark-candidates-only passes the 36-test CLI suite and
the 145-test ERT suite, whose integration half drives the variant against
scratch repositories: renames, copies, overlapping records, a containing
mark superseding a record anchored elsewhere, a mark after a rename leaving
no ghost, a write to a broken sidecar refused. mark-candidates-only fails
exactly that last test.

On the fixtures, `coverage --json`, `status --json`, `stale --json` and the
sidecar and output of both marks, timestamps aside, hash identically for the
baseline, `combined`, `combined-parallel`, `combined-commit-diff` and
`combined-parallel-commit-diff` at 5,000 files clean and stale with 1 and 20
records, and at 10,000 files stale with 1 record. The baseline check at
5,000 files, 20 records, stale took 12 minutes.

## Timings

### coverage

| Files | Records | Source | baseline | primitives | worktree-cache | hunks-cache | sidecar-once | intervals | combined | combined-parallel | combined-commit-diff | combined-parallel-commit-diff |
| ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 5,000 | 1 | clean | 3.08 (3.05-3.19) | 1.15 (1.11-1.18) | 1.94 (1.91-1.97) | 3.13 (3.07-3.19) | 3.02 (2.96-3.08) | 3.15 (3.11-3.19) | 0.73 (0.72-0.74) | 0.79 (0.78-0.81) | | |
| 5,000 | 1 | stale | 15.0 (14.9-15.2) | 11.8 (11.6-11.9) | 17.2 (17.2-17.2) | 19.1 (16.0-22.2) | 18.7 (16.5-20.9) | 22.0 (21.5-22.5) | 20.3 (19.9-21.0) | 19.1 (13.9-22.0) | 1.72 (1.72-1.75) | 1.75 (1.69-1.81) |
| 5,000 | 20 | clean | 39.9 (34.6-44.1) | 8.86 (8.61-9.10) | 4.09 (4.07-4.12) | 30.0 (29.9-30.0) | 34.5 (34.2-34.9) | 30.0 (29.4-30.5) | 2.06 (2.00-2.17) | 2.32 (2.27-2.33) | | |
| 5,000 | 20 | stale | >120 | >120 | >120 | 70.1 (66.2-73.9) | >120 | >120 | 21.5 (21.3-25.5) | 20.9 (20.1-22.5) | 5.21 (5.20-5.27) | 5.47 (5.46-5.49) |
| 10,000 | 1 | clean | 6.00 (5.87-6.06) | 2.04 (2.01-2.06) | 3.67 (3.60-3.75) | 5.82 (5.82-5.82) | 5.62 (5.59-5.64) | 5.73 (5.70-5.76) | 1.35 (1.31-1.36) | 1.45 (1.42-1.50) | | |
| 10,000 | 1 | stale | 28.1 (27.9-28.2) | 39.6 (38.6-40.6) | 38.8 (38.6-39.0) | 30.7 (29.6-31.9) | 27.8 (27.6-27.9) | 28.2 (28.1-28.4) | 39.0 (38.4-39.3) | 45.7 (39.9-50.4) | 3.34 (3.32-3.38) | 3.48 (3.46-3.52) |
| 10,000 | 20 | clean | 57.4 (57.4-57.5) | 17.2 (17.1-17.3) | 8.06 (8.05-8.07) | 58.9 (58.7-59.1) | 57.6 (57.3-57.9) | 58.3 (58.2-58.3) | 3.93 (3.85-3.96) | 4.61 (4.52-4.67) | 4.12 (4.02-4.14) | 4.72 (4.70-4.74) |
| 10,000 | 20 | stale | >120 | >120 | >120 | 116.3 (116.0-116.5) | >120 | >120 | 49.7 (48.0-49.8) | 49.1 (46.5-49.3) | 11.0 (10.8-11.0) | 11.9 (11.3-12.1) |

The baseline at 5,000 files, 20 records, stale completed in 232 s under the
profiler. The 10,000-file stale baseline never completed within a limit.

The commit-diff variant alone, on top of hunks-cache but without the other
changes, gives 12.2 s at 5,000 files with 1 record stale, 51.1 s at 20
records stale, and 24.0 s and 108 s at 10,000 files.

### mark

| Files | Records | Source | baseline | combined | combined-parallel | combined-commit-diff | combined-parallel-commit-diff | mark-candidates-only |
| ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 5,000 | 1 | clean | 0.28 (0.28-0.28) | 0.29 (0.29-0.29) | 0.23 (0.22-0.23) | | | 0.13 (0.13-0.14) |
| 5,000 | 1 | stale | 0.32 (0.31-0.32) | 0.32 (0.32-0.33) | 0.30 (0.27-0.30) | 0.49 (0.48-0.50) | 0.47 (0.47-0.49) | 0.16 (0.16-0.18) |
| 5,000 | 20 | clean | 1.16 (1.15-1.16) | 1.27 (1.26-1.30) | 0.51 (0.49-0.54) | | | 0.14 (0.13-0.15) |
| 5,000 | 20 | stale | 1.37 (1.37-1.39) | 1.31 (1.31-1.32) | 0.55 (0.51-0.57) | 2.04 (1.99-2.08) | 1.30 (1.27-1.31) | 0.37 (0.36-0.38) |
| 10,000 | 1 | clean | 0.47 (0.47-0.48) | 0.50 (0.49-0.51) | 0.43 (0.42-0.45) | | | 0.21 (0.20-0.21) |
| 10,000 | 1 | stale | 0.51 (0.50-0.51) | 0.54 (0.54-0.55) | 0.45 (0.42-0.45) | 0.94 (0.91-0.95) | 0.83 (0.79-0.87) | 0.24 (0.24-0.24) |
| 10,000 | 20 | clean | 2.14 (2.14-2.16) | 2.40 (2.37-2.41) | 0.92 (0.91-0.92) | 2.55 (2.49-2.56) | 0.92 (0.92-0.93) | 0.20 (0.20-0.21) |
| 10,000 | 20 | stale | 2.55 (2.52-2.55) | 2.56 (2.56-2.62) | 0.95 (0.94-1.07) | 3.99 (3.98-4.12) | 2.63 (2.57-2.63) | 0.54 (0.53-0.54) |

The single-change variants are within 5% of the baseline on mark, except
sidecar-once, which is 8 to 13% slower: mark already parses each sidecar
once, so the cache only adds bookkeeping. The mark of lines 1-60, which
supersedes records, tracks the mark outside them within 0.1 s in every
cell.

### 100 records per file

| Files | Source | Operation | baseline | combined | combined-parallel | combined-parallel-commit-diff |
| ---: | --- | --- | ---: | ---: | ---: | ---: |
| 5,000 | clean | coverage | >120 | 7.72 (7.62-7.82) | 9.43 (9.28-9.58) | |
| 5,000 | stale | coverage | >120 | 40.0 (39.9-40.1) | 40.8 (40.8-40.8) | 22.4 (22.2-22.6) |
| 5,000 | clean | mark | 4.79 | 5.34 (5.33-5.35) | 1.78 (1.77-1.80) | |
| 5,000 | stale | mark | 6.37 | 5.59 (5.58-5.59) | 1.61 (1.58-1.64) | 5.75 (5.73-5.78) |
| 10,000 | clean | coverage | >120 | 17.6 (17.5-17.8) | 21.4 (20.8-21.9) | |
| 10,000 | stale | coverage | >120 | >120 | >120 | 48.5 (47.9-49.0) |
| 10,000 | clean | mark | 9.94 | 11.7 (11.6-11.7) | 4.03 (4.01-4.05) | |
| 10,000 | stale | mark | 11.5 | 12.3 (12.2-12.3) | 3.90 (3.79-4.01) | 12.6 (11.8-13.5) |

At a million records the parse alone is 12.9 s single-threaded and the
combined variant holds 1.5 GB.

### Cache hints

`posix_fadvise(DONTNEED)` on every file in the repository after `sync`,
then three fresh runs. A hint, not a verified cold cache: `drop_caches` is
read-only in this container.

| 10,000 files, 20 records, clean | first run after hint | next two |
| --- | ---: | ---: |
| coverage, baseline | 69.3 | 63.5, 64.7 |
| coverage, combined-parallel | 10.8 | 4.9, 4.9 |
| mark, baseline | 6.1 | 2.6, 2.5 |
| mark, combined-parallel | 1.09 | 0.94, 0.93 |

## What the changes did, and what they cost

The clean workload is now bounded by the sidecar parse. In the combined
variant at 10,000 files and 20 records, `parse-sidecar` is 2.45 s of 5.8 s
profiled; `resolve-region` and `candidate-paths` over 200,000 records are
1.3 s; reading 10,000 files once is 0.9 s. The parallel pass does not help
coverage, since the sequential parse that follows already finds the cache
full and the work is spread thin; it does halve mark, whose parse is the
whole cost: 13.6 s of CPU across cores in 1.0 s of wall time.

The stale workload is now bounded by the moved-block scan. In
`combined-commit-diff` at 10,000 files and 20 records, the 6,000 stale
records hash 1.3 million windows, 8.5 s of 16.4 s profiled; the parse is
2.3 s; the one `git diff` is 0.9 s. The scan repeats per record what the
file's 3 stale records could share, and every window hash re-trims the same
lines.

The caches cost memory and, on the stale workload, cost subprocess time
until commit-diff removes the subprocesses. Peak RSS at 10,000 files and 20
records: baseline 322 MB, combined 590 MB, combined-parallel 932 MB.
`read-worktree` keeps both the text and the line vector of every file. The
combined variant without commit-diff is slower than the baseline at one
record per file, stale: 39 s against 28 s at 10,000 files. The profile puts
the difference in the 4,000 subprocesses, 8 ms each against 3 to 4 ms in the
baseline, with system time doubled. A direct check found spawn cost rising
from 3.0 ms to 3.7 ms per process when the parent retains 400 MB, so
memory explains part of it; the rest is unattributed, and subprocess-bound
cells varied between runs by up to 1.7x with no code change, where
CPU-bound cells stayed within 5%. The conclusion holds either way: the
number of subprocesses is the lever, not their individual cost.

commit-diff as written runs `git diff` over the whole tree per commit, so
mark pays for it too: 2.55 s to 3.99 s at 10,000 files, 20 records, stale,
where 2,000 files are dirty. Restricting the pathspec to the paths of the
records that cite the commit would remove that; it was not measured.

## Gaps against the targets

Normal workload is 10,000 files, 20 records per file, on this machine.

| Target | Best measured, results unchanged | Gap |
| --- | ---: | --- |
| mark under 500 ms, clean | 0.92 s, parallel parse | 1.8x; the parse is 2.0 s of CPU |
| mark under 500 ms, stale | 0.95 s | same |
| coverage under 5 s, clean | 3.9 s | met, with 1 s to spare |
| coverage under 5 s, stale | 11.0 s | 2.2x; 8.5 s is the moved-block scan |
| editor display under 100 ms | not measured | unverified; nothing ran in Emacs |

Mark's floor with the parse skipped is 0.20 s, so the parse is the whole gap.
Three ways close it, and only the third needs a file outside the store: a
faster reader for the fixed layout of ADR-0014, which replaces `edn/read-string`
and was not tried; parallel parse plus a narrower contract; or a disposable
parse-verdict cache keyed by sidecar path, size and mtime, which lets a mark
skip re-parsing sidecars it has seen and read only the ones that changed. The
measurements justify that cache for mark alone, and only if 500 ms at 20
records per file is a hard target: at 1 record per file mark is already 0.43 s,
and coverage gains nothing from it, since coverage needs every record anyway.
A verdict cache holds no review state; a stale or missing cache costs one full
parse, never a wrong answer.

## Next implementation plan

Seven tickets, linked to lgu-01m21qtzrcfq, each bounded to one measured
cost. The blocking edges are the order the measurements impose: a later
change is the top cost only after the earlier one lands, and the same
functions change each time.

1. lgu-01m249ccrj5h, the primitives. No blocker.
2. lgu-01m249ccvy6a, read each file once, parse each sidecar once, count
   over intervals, with a memory bound. Blocked on 1.
3. lgu-01m249cczbsw, one `git diff` per stored commit, restricted to the
   records' paths. Blocked on 2.
4. lgu-01m249cd2vt1, share the moved-block scan across a file's records.
   Blocked on 3, since the scan is the top cost only then.
5. lgu-01m249cd6dgq, parse the store on every core in mark. Blocked on 2.
6. lgu-01m249cd9v2h, decide how mark stops paying for the full parse: a
   fixed-layout reader, a narrower contract, or the parse-verdict cache.
   Human in the loop; blocked on 5, so the decision rests on the parallel
   number.
7. lgu-01m249cddd06, measure the editor-display target in Emacs. Blocked
   on 5.

Invariants every ticket keeps: review state lives in the committed store and
nowhere else (ADR-0010); renames are followed and copies never (ADR-0009);
a mark supersedes only what it contains (ADR-0013); a write names every
sidecar it cannot read; the sidecar layout of ADR-0014 does not change.

Overlap with the closed tickets: lgu-01m147ksxdnm made mark anchor only
candidate sidecars, and these tickets leave that filter alone; what remains
of mark is the parse it kept. lgu-01m147n30cnf's `regions` query reads every
sidecar for the same reason, so tickets 2 and 5 change its cost too, and
ticket 7 is where the editor number gets measured. Neither closed ticket is
reopened.

## Unmeasured

Cold disk; real repositories, where records cite many commits and commit-diff
runs once per commit; a pathspec-restricted commit-diff; a faster sidecar
reader; sharing the moved-block scan across records; `status`, `next` and
`regions` beyond the equivalence hashes; memory limits; the Emacs package.

## Reproduction

Branch `prototype/mark-coverage-latency`, commit
`728137f06d10a0a49c37f62540f1daf02b089710`, holds the scripts, patches, raw
results and profiles under `docs/experiments/latency-prototype/`. Scripts
run from a scratch copy of that directory and need `bb`, `git`, Python 3 and,
for the ERT runs, Emacs.

```sh
python3 bench.py build 10000 20                 # repos/f10000-d20
python3 make_variants.py /absolute/path/to/legu # variants/<name>/legu, patches/<name>.diff
LEGU_SRC=/absolute/path/to/legu ./matrix.sh     # the timing matrix, appends results.jsonl
LEGU_SRC=/absolute/path/to/legu ./verify.sh     # ERT, profiles, equivalence checks
LEGU_SRC=/absolute/path/to/legu ./verify2.sh    # the same for the commit-diff variants
python3 summarize.py tables                     # the tables above
python3 summarize.py profiles                   # per-function attribution
python3 summarize.py checks                     # output hashes per variant
```

`bench.py profile` runs one command under `profile.clj`; `micro.clj` and
`spawn.clj` are the primitive and spawn-cost checks.
