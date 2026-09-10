---
id: lgu-01m249ccvy6a
title: Read each source file once and parse each sidecar once per run
status: closed
type: task
priority: 2
mode: afk
created: '2026-09-09T23:52:20.091853319Z'
updated: '2026-09-10T12:37:48.667105188Z'
closed: '2026-09-10T12:37:48.667105188Z'
acceptance:
- title: Clean coverage at 10,000 files and 20 records completes under 5 s on the experiment's fixture, measured with three fresh-process trials recorded on the ticket
  done: true
- title: coverage, status, stale and next --json hash identically before and after on the 5,000-file fixtures, clean and stale, at 1 and 20 records
  done: true
- title: The CLI suite and the full ERT suite pass, including the write to a broken sidecar being refused
  done: true
- title: Peak RSS at 10,000 files and 20 records is recorded on the ticket and stays under 400 MB
  done: true
deps:
- lgu-01m249ccrj5h
links:
- lgu-01m21qtzrcfq
- lgu-01m249ccrj5h
- lgu-01m249cczbsw
- lgu-01m249cd2vt1
- lgu-01m249cd6dgq
- lgu-01m249cd9v2h
- lgu-01m249cddd06
external_refs:
- git:2a05369bdb3348a99fbdceaca300a12d8bd714ee
---

## Description

Coverage reads, hashes and splits every source file once per record plus
once for eligibility: 210,000 `read-worktree` calls for 10,000 files at 20
records, 59 s of 66 s in the baseline profile. It parses every sidecar
twice, in `skipped-paths` and again in `records`. Coverage also expands
every record into a per-line set before counting.

Remember `read-worktree` per path for the run, since legu never writes a
source file; remember each `parse-sidecar` result and the store enumeration
until `save-state!` writes that sidecar; count coverage over merged line
intervals and build the per-line sets `status` and `next` print from the
merged intervals. The patches are `worktree-cache.diff`, `sidecar-once.diff`
and `intervals.diff` on branch prototype/mark-coverage-latency; combined with
the primitives they measured 3.9 s on clean coverage at 10,000 files and 20
records, against 57 s.

Bound the memory. The prototype kept both the text and the line vector of
every file and peaked at 590 MB at 200,000 records and 1.5 GB at a million;
keep what anchoring needs and drop the rest, and record the peak RSS on the
ticket. The `errors` contract stands: every sidecar is still parsed on every
command, once.

## Notes

**2026-09-10T12:11:26.146177126Z**

Where the committed change (2a05369) departs from the description, and why:

- read-worktree keeps the text, the hash and a line count of every file it reads, and the line vector as a delay. The delay is forced only when anchoring looks inside a file whose hash no longer matches a record. A clean file is split once to count its lines and never kept split. A stale file is split once, where the prototype split it once per record. The text stays resident for every file read: dropping it would mean reading a changed file twice, and the peak RSS below leaves room for it.
- status and next print the merged ranges directly, with no per-line sets built from them. The output is byte-identical: fmt-ranges printed a set by first collapsing it into the same ranges.
- The interval helpers are named merge-ranges, subtract-ranges and range-lines, matching fmt-ranges, the JSON ranges key and the Emacs side's legu--ranges-*.
- save-state! drops both the parse of the sidecar it writes and the store listing. Dropping the parse is guarded: without it, three ERT integration tests fail. Dropping the listing is not observable today, since no command lists the store again after it writes. It stays because the description asks for it.

**2026-09-10T12:36:50.488793363Z**

Clean coverage --json at 10,000 files and 20 records per file, on the experiment's fixture (bench.py build 10000 20). Three fresh bb processes per binary, warm page cache, run serially with none of this session's other jobs running, 2026-09-10. The host carried a load average of about 3.5 from other work throughout.

- before, legu at 28dd25c (sha256 b6de9698...): 15.7 s median, 15.6 to 15.8 s; peak RSS 293 to 295 MB
- after, legu at 2a05369 (sha256 fc8db68e..., byte for byte the committed file): 3.45 s median, 3.41 to 3.60 s; peak RSS 350 MB in each of the three trials

Every trial printed the same output, sha256 feeba172dd0c..., the hash the previous ticket recorded for this cell. The prototype's combined variant measured 3.93 s and peaked at 590 MB.

**2026-09-10T12:36:50.592830700Z**

Output hashes on the 5,000-file fixtures, before (28dd25c) and after (2a05369). Each is the sha256 of stdout, first 12 hex digits, from bench.py check with next added to its operations:

| Records | State | Command | Before | After |
| ---: | --- | --- | --- | --- |
| 1 | clean | coverage --json | d7975d17e73c | d7975d17e73c |
| 1 | clean | status --json | e99508dd9602 | e99508dd9602 |
| 1 | clean | stale --json | c6f799f7bbe3 | c6f799f7bbe3 |
| 1 | clean | next --json | de22b6b53fca | de22b6b53fca |
| 1 | stale | coverage --json | b2266e932b76 | b2266e932b76 |
| 1 | stale | status --json | ce37cf50d4a6 | ce37cf50d4a6 |
| 1 | stale | stale --json | dd0925a439ee | dd0925a439ee |
| 1 | stale | next --json | 2b1fc81057dd | 2b1fc81057dd |
| 20 | clean | coverage --json | 42218e868738 | 42218e868738 |
| 20 | clean | status --json | 58aebe26f179 | 58aebe26f179 |
| 20 | clean | stale --json | c6f799f7bbe3 | c6f799f7bbe3 |
| 20 | clean | next --json | 32858072bd89 | 32858072bd89 |
| 20 | stale | coverage --json | fb9b2a9c70be | fb9b2a9c70be |
| 20 | stale | status --json | b19557e0d12a | b19557e0d12a |
| 20 | stale | stale --json | f7ddc49bd068 | f7ddc49bd068 |
| 20 | stale | next --json | 8163618bc5b4 | 8163618bc5b4 |

The before check at 5,000 files, 20 records, stale took 18 minutes for the four commands.

**2026-09-10T12:37:48.667105188Z**

Coverage now reads each source file once, parses each sidecar once and lists the store once per run, and counts lines over merged ranges instead of per-line sets. Clean coverage at 10,000 files and 20 records dropped from 15.7 s to 3.45 s, with a peak RSS of 350 MB. coverage, status, stale and next print the same bytes on the 5,000-file fixtures. The line vector is a delay held in the cache entry, forced only when anchoring looks inside a changed file. That keeps memory under the 400 MB bound where the prototype, which kept every file's lines, reached 590 MB.
