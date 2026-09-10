---
id: lgu-01m249cczbsw
title: Anchor through one git diff per stored commit
status: closed
type: task
priority: 1
mode: afk
created: '2026-09-09T23:52:20.201028689Z'
updated: '2026-09-10T14:01:57.317838383Z'
closed: '2026-09-10T13:54:55.770374865Z'
acceptance:
- title: Stale coverage at 10,000 files and 20 records completes under 15 s on the experiment's fixture, three fresh-process trials recorded on the ticket
  done: true
- title: mark on the same stale fixture is no slower than before the change, recorded on the ticket
  done: true
- title: coverage, status and stale --json hash identically before and after on the stale fixtures at 5,000 and 10,000 files, 1 and 20 records
  done: true
- title: The ERT integration tests for renames, copies, shifted and moved blocks, and marks after renames pass
  done: true
deps:
- lgu-01m249ccvy6a
links:
- lgu-01m21qtzrcfq
- lgu-01m249ccrj5h
- lgu-01m249ccvy6a
- lgu-01m249cd2vt1
- lgu-01m249cd6dgq
- lgu-01m249cd9v2h
- lgu-01m249cddd06
external_refs:
- git:fcc56a18dae995646365cd0fb9bb45db9a9919f2
- git:38ddb5b51dc6402d246f661f4226fbff0375a380
---

## Description

On the stale workload every record in an edited file runs its own `git show`
and its own `git diff --no-index`: 40,000 subprocesses at 5,000 files and 20
records, 167 s of 232 s. The 20 records of one file share both answers, and
`git diff -U0 <commit> -- <paths>` answers for every file at once.

For a record anchoring at its own path, when git tracks that path, take the
hunks from one `git diff -U0 --no-renames <commit> -- <paths>` per distinct
stored commit, where `<paths>` are the stored paths of the records citing
that commit; parse the output into path to hunks. Any other case keeps the
per-file route: a candidate path from a rename or an added file, an
untracked path, a path git quotes in the diff header, and the old-text scan
of the moved-block fallback, which still needs `git show`, taken lazily.

The prototype, `commit-diff.diff` on branch prototype/mark-coverage-latency,
diffs the whole tree per commit and measured stale coverage at 10,000 files
and 20 records at 11.0 s against more than 120 s, with identical output; it
also made mark 1.4 s slower on that workload because mark paid for the
whole-tree diff. The pathspec is what keeps mark's cost proportional to the
records it anchors.

Hunks from `git diff <commit>` and from `--no-index` over the same bytes are
the same hunks under the default diff configuration; the equivalence check
covers it, and any `diff.*` config that could split them is out of scope.
ADR-0009 stands: a rename is followed, a copy never.

## Notes

**2026-09-10T13:54:55.268881967Z**

Stale coverage and mark at 10,000 files and 20 records per file, on the experiment's fixture (bench.py build 10000 20, state stale: the first twenty lines of every fifth file edited). Three fresh bb processes per cell, warm page cache, run serially with none of this session's other jobs running, 2026-09-10. The host carried a load average of 3.4 to 3.9 from other work throughout.

- coverage, after (legu at fcc56a1, byte for byte the committed file): 10.1 s median, 9.93 to 10.34 s.
- coverage, before (legu at 3d51ca6): not timed on its own. The before hash check ran coverage, status and stale on this cell in about 43 minutes together, roughly 14 minutes a command.
- mark outside every record (src/d0000/f00000.txt:201-210, a file the stale state edits): before 3.11 s median, 3.00 to 3.18 s; after 2.83 s median, 2.78 to 2.83 s.

**2026-09-10T13:54:55.404920079Z**

Output hashes on the stale fixtures, before (3d51ca6) and after (fcc56a1). Each is the sha256 of stdout, first 12 hex digits, from bench.py check; the marks hash stdout plus the written sidecar, timestamps masked. The 5,000-file, 20-record rows for coverage, status and stale are also the hashes the read-once ticket recorded for that cell.

| Files | Records | Command | Before | After |
| ---: | ---: | --- | --- | --- |
| 5,000 | 1 | coverage --json | b2266e932b76 | b2266e932b76 |
| 5,000 | 1 | status --json | ce37cf50d4a6 | ce37cf50d4a6 |
| 5,000 | 1 | stale --json | dd0925a439ee | dd0925a439ee |
| 5,000 | 1 | mark outside | d281f69369cc | d281f69369cc |
| 5,000 | 1 | mark of lines 1-60 | 6f8784abb580 | 6f8784abb580 |
| 5,000 | 20 | coverage --json | fb9b2a9c70be | fb9b2a9c70be |
| 5,000 | 20 | status --json | b19557e0d12a | b19557e0d12a |
| 5,000 | 20 | stale --json | f7ddc49bd068 | f7ddc49bd068 |
| 5,000 | 20 | mark outside | 49b2ce2bedbc | 49b2ce2bedbc |
| 5,000 | 20 | mark of lines 1-60 | 4402d6add4cb | 4402d6add4cb |
| 10,000 | 1 | coverage --json | ae38d504a7bf | ae38d504a7bf |
| 10,000 | 1 | status --json | 63a73f8863dc | 63a73f8863dc |
| 10,000 | 1 | stale --json | 02774886e52a | 02774886e52a |
| 10,000 | 1 | mark outside | 14785b835908 | 14785b835908 |
| 10,000 | 1 | mark of lines 1-60 | 3ee7555663da | 3ee7555663da |
| 10,000 | 20 | coverage --json | 182b3d062844 | 182b3d062844 |
| 10,000 | 20 | status --json | f8de3bf177a3 | f8de3bf177a3 |
| 10,000 | 20 | stale --json | c4b124889e1a | c4b124889e1a |
| 10,000 | 20 | mark outside | ffa519364e99 | ffa519364e99 |
| 10,000 | 20 | mark of lines 1-60 | c24e548174ef | c24e548174ef |

The before check at 10,000 files, 20 records, stale took about 43 minutes for the five commands.

**2026-09-10T13:54:55.534316813Z**

Where the committed change (fcc56a1) goes past the description, and what it leaves alone:

- A file new since the record's commit, a deleted one, and one git's attributes call binary drop out of the batched map and take the per-file route. A new file would otherwise come back as one hunk of every line and shift the region off its place; an ERT test pins that case.
- forget with a line range also batches, since it anchors every record in the store. The description did not name it.
- The diff runs with --literal-pathspecs, --no-textconv, --no-ext-diff, --no-color and explicit a/ b/ prefixes, and splits its pathspec into runs under 100,000 characters.
- Left as they are: `git diff <commit>` reads the working-tree side through git's clean filters and line-ending conversion (core.autocrlf, text and eol attributes, an LFS filter), where `--no-index` reads raw bytes; and it reads a path marked assume-unchanged or skip-worktree from the index. Both are configuration of the same kind the description puts out of scope for diff.*. The spec review ran core.autocrlf=true with a CRLF working tree over an LF commit and got the same regions answer before and after.

**2026-09-10T13:54:55.770374865Z**

Records anchoring at their own tracked path take their hunks from one git diff -U0 --no-renames per stored commit, restricted to the files being anchored, instead of a git show and a git diff --no-index each. Stale coverage at 10,000 files and 20 records runs in 10.1 s, where it took about 14 minutes; mark on the same fixture went from 3.11 s to 2.83 s. coverage, status, stale and both marks hash identically before and after on the four stale fixtures. Three new ERT tests pin a record older than its file, two records citing different commits, and a quoted path beside a plain one.

**2026-09-10T14:01:57.205092161Z**

Clean coverage, which the criteria did not ask about but which the change touches: fetch-hunks! looks at every record on a clean tree too. Same fixture and method as the stale timings, 10,000 files and 20 records, three fresh processes each, load average 2.5 to 3.5.

- before (3d51ca6): 3.82 s median, 3.80 to 3.93 s, peak RSS 350 MB. A second window gave 3.83 s.
- fcc56a1: 4.13 s median, 4.08 to 4.17 s, peak RSS 388 MB. resolve-regions held all 200,000 results in a vector, and needs-hunks? ran the commit check and the tracked set ahead of the hash.
- 38ddb5b, which asks the hash first and returns the results lazily: 3.92 s median, 3.91 to 3.97 s, peak RSS 348 MB.

Re-measured with 38ddb5b in the same window: stale coverage 10.06 s median, 9.92 to 10.22 s, peak RSS 437 MB. The stale peak was not measured before, since the old code took about 14 minutes on this cell. mark was 2.82 s median, against 3.04 s before. coverage, status, stale and both marks hash identically to 3d51ca6 on the clean 10,000-file, 20-record fixture and on the stale 10,000- and 5,000-file, 20-record fixtures. Both suites pass: ERT 151 tests with 6 evil tests skipped, and the 36 CLI tests.
