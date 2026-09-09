---
id: lgu-01m249ccvy6a
title: Read each source file once and parse each sidecar once per run
status: open
type: task
priority: 2
mode: afk
created: '2026-09-09T23:52:20.091853319Z'
updated: '2026-09-09T23:52:20.762003493Z'
acceptance:
- title: Clean coverage at 10,000 files and 20 records completes under 5 s on the experiment's fixture, measured with three fresh-process trials recorded on the ticket
  done: false
- title: coverage, status, stale and next --json hash identically before and after on the 5,000-file fixtures, clean and stale, at 1 and 20 records
  done: false
- title: The CLI suite and the full ERT suite pass, including the write to a broken sidecar being refused
  done: false
- title: Peak RSS at 10,000 files and 20 records is recorded on the ticket and stays under 400 MB
  done: false
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
