---
id: lgu-01m249cd9v2h
title: Decide how mark stops paying for the full parse
status: open
type: task
priority: 2
mode: hitl
created: '2026-09-09T23:52:20.536743583Z'
updated: '2026-09-09T23:52:20.762003493Z'
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
