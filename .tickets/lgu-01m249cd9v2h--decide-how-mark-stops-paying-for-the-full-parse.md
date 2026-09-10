---
id: lgu-01m249cd9v2h
title: Decide how mark stops paying for the full parse
status: open
type: task
priority: 2
mode: hitl
created: '2026-09-09T23:52:20.536743583Z'
updated: '2026-09-10T14:06:33.026813719Z'
acceptance:
- title: A note on this ticket records the decision, the measurement it rests on, and the ADR it touches if any
  done: false
- title: If a cache outside the store is chosen, an ADR says what it holds, where it lives, and that a missing or stale cache changes no answer
  done: false
deps:
- lgu-01m249cd6dgq
links:
- lgu-01m21qtzrcfq
- lgu-01m249ccrj5h
- lgu-01m249ccvy6a
- lgu-01m249cczbsw
- lgu-01m249cd2vt1
- lgu-01m249cd6dgq
- lgu-01m249cddd06
- lgu-01m25t7y4zzf
- lgu-01m25t8643d6
---

## Description

With the parse spread over every core, mark at 10,000 files and 20 records
is 0.92 s against a 500 ms target, and 0.20 s once the parse of sidecars
that cannot hold a superseded record is skipped. The skip fails the test
that pins the write's contract to name every unparseable sidecar. The
experiment measured no way to meet the target while every sidecar is parsed
on every mark on one core.

Three ways close the gap; pick one, or decide the target is the parallel
number. A reader for the fixed layout of ADR-0014 that replaces
`edn/read-string`, untried, and the only one that helps coverage too. A
narrower contract, where mark names the unparseable sidecars it read rather
than all of them. Or a disposable parse-verdict cache keyed by sidecar path,
size and mtime, outside the store, so a mark re-parses only sidecars that
changed since the last run: the one option that adds a file, and the only
one the measurements justify calling an index. It would hold no review
state, the committed store stays authoritative, and a stale or missing cache
costs one full parse, never a wrong answer. Coverage gains nothing from it,
since coverage needs every record.

Whichever is chosen, ADR-0010 stands: the CLI is the single owner of the
store, and nothing outside `.review/` is read as review state.

## Notes

**2026-09-10T10:52:06.176449298Z**

edamame, bundled with babashka, was measured against clojure.edn on
synthetic sidecars in the fixed layout, 2,000 iterations each, warm:

| Sidecar | edn/read-string | edamame default | edamame :all false |
| --- | ---: | ---: | ---: |
| 1 record, 342 bytes | 15 us | 22 us | 18 us |
| 20 records, 6 KB | 172 us | 252 us | 253 us |
| 100 records, 30 KB | 881 us | 1335 us | 1341 us |

Same value from all three. edamame is about 1.5x slower here, so it is not
the faster reader this ticket weighs. The 172 us per 20-record sidecar
matches the 2.0 s parse of 10,000 sidecars in mark's profile. A faster
reader would have to be written for the ADR-0014 layout itself.

**2026-09-10T14:06:33.026813719Z**

The store format is moving before this decision is taken. ADR-0015 changes
sidecars to JSON Lines, one record per line, for the count of changed lines
in pull requests, and lgu-01m25t7y4zzf lands it. That is the first of the
three options above by another route: the reader that replaces
`edn/read-string` is cheshire, which already ships, rather than a reader
written for the ADR-0014 layout. A scratch benchmark on 10,000 sidecars of
20 records, warm, in one bb process, read and parsed the tree in 0.75 s as
JSONL against 2.37 s as EDN, about 3.2x, at 61.1 MB against 62.8 MB raw.

Sequence: lgu-01m25t7y4zzf, then lgu-01m249cd6dgq re-measured on the new
format, then this decision with both numbers. If the two together bring mark
under 500 ms on one machine's core count, the cache outside the store is not
needed and the narrower contract is not either.
