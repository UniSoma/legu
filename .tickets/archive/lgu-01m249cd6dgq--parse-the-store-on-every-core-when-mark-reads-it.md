---
id: lgu-01m249cd6dgq
title: Parse the store on every core when mark reads it
status: closed
type: task
priority: 2
mode: afk
created: '2026-09-09T23:52:20.426609585Z'
updated: '2026-09-10T14:59:28.195870695Z'
closed: '2026-09-10T14:59:28.195870695Z'
acceptance:
- title: mark at 10,000 files and 20 records completes under 1 s on the experiment's fixture, three fresh-process trials recorded on the ticket, with the core count
  done: true
- title: The ERT test that a write to a broken sidecar is refused, and the CLI suite, pass
  done: true
- title: The sidecar written by mark is byte-identical to the one written before the change, timestamp aside
  done: true
deps:
- lgu-01m249ccvy6a
- lgu-01m25t7y4zzf
links:
- lgu-01m21qtzrcfq
- lgu-01m249ccrj5h
- lgu-01m249ccvy6a
- lgu-01m249cczbsw
- lgu-01m249cd2vt1
- lgu-01m249cd9v2h
- lgu-01m249cddd06
- lgu-01m25t7y4zzf
- lgu-01m25t8643d6
external_refs:
- git:d00fdd7daa6f6952fcffe777042e358c947f2513
---

## Description

Mark at 10,000 files and 20 records is 2.1 s, of which 2.0 s parses every
sidecar so the write can name the ones it cannot read. The parse is
independent per sidecar. `pmap` over the parse pass, filling the per-run
sidecar cache, measured 0.92 s on the same fixture (patch `parallel` inside
`combined-parallel.diff` on branch prototype/mark-coverage-latency), with
the broken-sidecar refusal test still passing.

Fill the cache in parallel before the sequential purge, in `mark`, `ticket`
and `forget`. `store-errors` is an atom and the cache is an atom, so the
parallel pass needs no other coordination. Record the wall time and the CPU
time on the ticket: the parallel pass spends 13.6 s of CPU for 1.0 s of
wall on this machine, and on a machine with fewer cores the gain is smaller.

## Notes

**2026-09-10T14:59:27.974618270Z**

mark at 10,000 files and 20 records, on the latency experiment's fixture (bench.py build 10000 20, the schema 3 generator at 7762cd6): mark of src/d0000/f00000.txt:201-210, clean, three fresh bb processes per binary, warm page cache, every core (no taskset). The host has 32 logical cores (i9-13900HX), and carried a load average of 2.7 to 2.9 from other work. Babashka 1.13.220, 2026-09-10.

- before, legu at 4d0a4d6 (sha256 b2fd83ace933...)
- after, legu at d00fdd7 (sha256 9dfbba8f3212..., byte for byte the committed file)

| | trial | wall s | user CPU s | sys CPU s | peak RSS MB |
| --- | ---: | ---: | ---: | ---: | ---: |
| before | 1 | 1.220 | 0.96 | 0.32 | 208 |
| before | 2 | 1.239 | 0.95 | 0.36 | 208 |
| before | 3 | 1.244 | 0.94 | 0.37 | 208 |
| after | 1 | 0.850 | 3.13 | 0.74 | 232 |
| after | 2 | 0.827 | 2.87 | 0.72 | 236 |
| after | 3 | 0.810 | 2.82 | 0.81 | 236 |

About 3.7 s of CPU for 0.83 s of wall, where the description's EDN measurement spent 13.6 s for 1.0 s. On fewer cores the gain is smaller: the before binary is what one core gets.

The sidecar mark writes is unchanged. bench.py check --ops mark,mark-inside hashes stdout plus the written sidecar, timestamp masked, and gives the same hashes before and after: mark outside every record a7f8430a9cdd, mark of lines 1-60 that supersedes records 14088264f94a. A direct cmp of the two written sidecars, timestamp masked, is identical for both.

The CLI suite passes, 45 tests, including a new case: with 43 broken sidecars in the store, mark, ticket and forget each exit 0 and name every one on stderr and under errors, in path order. It passes before the change too, as the guard it is. The ERT suite passes, 151 tests with 145 as expected and 6 skipped (the evil group), including legu-test-integration-a-write-to-a-broken-sidecar-is-refused. Its integration half runs only with legu on PATH and otherwise skips all 64 tests without failing.

Where the change departs from the description: the prototype mapped read-state; this maps parse-sidecar. Only the sidecar cache is filled from the parallel threads, and store-errors is recorded by the sequential reads that follow, as before. forget runs the parallel pass before it reads every record to fetch hunks, not only before its purge loop.

**2026-09-10T14:59:28.195870695Z**

mark, ticket and forget now parse every sidecar with pmap into the per-run cache before their sequential pass. mark at 10,000 files and 20 records went from 1.22-1.24 s to 0.81-0.85 s on 32 cores, for about 3.7 s of CPU. The sidecar it writes is byte-identical, timestamp aside, and the unreadable-sidecar report is unchanged.
