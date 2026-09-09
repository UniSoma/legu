---
id: lgu-01m249cd6dgq
title: Parse the store on every core when mark reads it
status: open
type: task
priority: 2
mode: afk
created: '2026-09-09T23:52:20.426609585Z'
updated: '2026-09-09T23:52:20.762003493Z'
acceptance:
- title: mark at 10,000 files and 20 records completes under 1 s on the experiment's fixture, three fresh-process trials recorded on the ticket, with the core count
  done: false
- title: The ERT test that a write to a broken sidecar is refused, and the CLI suite, pass
  done: false
- title: The sidecar written by mark is byte-identical to the one written before the change, timestamp aside
  done: false
deps:
- lgu-01m249ccvy6a
links:
- lgu-01m21qtzrcfq
- lgu-01m249ccrj5h
- lgu-01m249ccvy6a
- lgu-01m249cczbsw
- lgu-01m249cd2vt1
- lgu-01m249cd9v2h
- lgu-01m249cddd06
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
