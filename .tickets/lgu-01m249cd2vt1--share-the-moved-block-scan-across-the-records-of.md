---
id: lgu-01m249cd2vt1
title: Share the moved-block scan across the records of one file
status: open
type: task
priority: 2
mode: afk
created: '2026-09-09T23:52:20.312747857Z'
updated: '2026-09-09T23:52:20.762003493Z'
acceptance:
- title: Stale coverage at 10,000 files and 20 records is measured before and after, three fresh-process trials on the ticket
  done: false
- title: stale --json and coverage --json hash identically before and after on the stale fixtures
  done: false
- title: The ERT tests for a block moved within a file, and for a block with a twin at review time, pass
  done: false
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
