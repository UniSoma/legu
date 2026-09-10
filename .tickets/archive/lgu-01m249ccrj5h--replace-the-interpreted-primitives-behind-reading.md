---
id: lgu-01m249ccrj5h
title: Replace the interpreted primitives behind reading and hashing
status: closed
type: task
priority: 2
mode: afk
created: '2026-09-09T23:52:19.986371041Z'
updated: '2026-09-10T11:39:48.202462239Z'
closed: '2026-09-10T11:39:34.719608003Z'
acceptance:
- title: The CLI suite and the full ERT suite pass unchanged
  done: true
- title: coverage --json, status --json and stale --json on the 10,000-file, 20-record fixture from the experiment hash identically before and after, clean and stale
  done: true
- title: Clean coverage at 10,000 files and 20 records is measured before and after on the ticket; the experiment saw 57 s to 17 s
  done: true
links:
- lgu-01m21qtzrcfq
- lgu-01m249ccvy6a
- lgu-01m249cczbsw
- lgu-01m249cd2vt1
- lgu-01m249cd6dgq
- lgu-01m249cd9v2h
- lgu-01m249cddd06
external_refs:
- git:958d37f06564b4eee90d48e9afa44ebd2cc93b5a
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

## Notes

**2026-09-10T11:09:07.283492929Z**

Clean coverage --json at 10,000 files and 20 records per file, on the experiment's fixture (bench.py build 10000 20), three fresh bb processes each with a warm page cache, run serially with nothing else on the host, 2026-09-10:

- before, legu at 1493eb3 (sha256 d8f06893..., the binary the experiment measured): 58.8 s median, 57.1 to 59.7 s
- after, this ticket's change (sha256 e96ca65f...): 13.9 s median, 13.6 to 13.9 s

The experiment saw 57.4 s to 17.2 s.

lines-of keeps the CR-stripping regex instead of the endsWith check the description names, and runs it only on lines that hold a CR. The regex's $ also matches ahead of a final NEL (byte 0x85), so a line ending in CR NEL loses its CR; endsWith keeps it, which moves that line's content hash from sha256("nel\x85") to sha256("nel\r\x85"). The byte-semantics invariant wins over the named mechanism. An ERT test now pins those hashes, and fails on the prototype's patch.

**2026-09-10T11:39:34.617541917Z**

Output hashes (sha256 of stdout) on the experiment's 10,000-file, 20-record fixture, from bench.py check, before (sha256 d8f06893...) and after (sha256 e96ca65f...):

| State | Command | Before | After |
| --- | --- | --- | --- |
| clean | coverage --json | feeba172dd0c | feeba172dd0c |
| clean | status --json | d82964cc0c93 | d82964cc0c93 |
| clean | stale --json | c6f799f7bbe3 | c6f799f7bbe3 |
| stale | coverage --json | 182b3d062844 | 182b3d062844 |
| stale | status --json | f8de3bf177a3 | f8de3bf177a3 |
| stale | stale --json | c4b124889e1a | c4b124889e1a |

The stale check took 29 minutes before and 22 minutes after, for the three commands.

**2026-09-10T11:39:48.101057688Z**

Closed: binary-bytes?, hex, lines-of and try-anchor now run on the JVM, and coverage output is unchanged. Clean coverage at 10,000 files and 20 records dropped from 58.8 s to 13.9 s. lines-of keeps the CR regex behind a CR guard instead of endsWith, because endsWith moves the hash of a line ending in CR NEL. The committed code differs from the timed binary only in comments and a local binding in try-anchor.
