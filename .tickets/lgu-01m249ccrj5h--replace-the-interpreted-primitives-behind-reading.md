---
id: lgu-01m249ccrj5h
title: Replace the interpreted primitives behind reading and hashing
status: open
type: task
priority: 2
mode: afk
created: '2026-09-09T23:52:19.986371041Z'
updated: '2026-09-09T23:52:20.762003493Z'
acceptance:
- title: The CLI suite and the full ERT suite pass unchanged
  done: false
- title: coverage --json, status --json and stale --json on the 10,000-file, 20-record fixture from the experiment hash identically before and after, clean and stale
  done: false
- title: Clean coverage at 10,000 files and 20 records is measured before and after on the ticket; the experiment saw 57 s to 17 s
  done: false
links:
- lgu-01m21qtzrcfq
- lgu-01m249ccvy6a
- lgu-01m249cczbsw
- lgu-01m249cd2vt1
- lgu-01m249cd6dgq
- lgu-01m249cd9v2h
- lgu-01m249cddd06
---

## Description

Four constant-factor costs sit at the top of every profile in
docs/experiments/mark-and-coverage-latency.md, and none of them is an
algorithm: `binary-bytes?` loops over up to 8,000 bytes in the interpreter
(124 us per file, 26 s of a 57 s clean coverage at 10,000 files and 20
records); `hex` calls `format` once per byte of every digest (9 us per hash,
1.3 million hashes on the stale workload); `lines-of` splits with a regex
and replaces per line (78 us per file); and `try-anchor` scans the old text
for a moved block even when the current text held no match, though the old
text only decides anything when the current text held exactly one.

Replace them with `String.indexOf` of a NUL, `java.util.HexFormat`,
`String.split` with an `endsWith` check, and a scan of the old text guarded
by `(= 1 (count here))`. The patch is `patches/primitives.diff` on branch
prototype/mark-coverage-latency; it measured 57.4 s to 17.2 s on clean
coverage at 10,000 files and 20 records, and 28.1 s to 23.5 s under the
profiler on the stale workload at 1 record.

Byte semantics must not move: every byte still round-trips through latin-1,
a lone trailing CR is still dropped, the hash of a region is still the
SHA-256 of its trimmed lines joined by newlines, and the ERT test that pins
`legu--file-hash` against the CLI still passes.
