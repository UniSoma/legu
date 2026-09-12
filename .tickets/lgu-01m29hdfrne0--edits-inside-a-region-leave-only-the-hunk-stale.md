---
id: lgu-01m29hdfrne0
title: Edits inside a region leave only the hunk stale
status: open
type: task
priority: 1
mode: afk
created: '2026-09-12T00:48:56.597283094Z'
updated: '2026-09-12T00:48:57.260622929Z'
parent: lgu-01m29h4g9n4s
tags:
- ready-for-agent
- per-hunk-staleness
acceptance:
- title: A 150-line record edited in place at 73-97 reports stale 73-97 only; coverage counts 125 reviewed and 25 stale; next points at line 73
  done: false
- title: An edit that grows or shrinks reports the hunk's new lines stale and the fragment below moved by the difference
  done: false
- title: A pure insertion inside reports the inserted lines stale and the fragment below reviewed and moved
  done: false
- title: Edits only above the region, and insertions right before or right after it, report the whole record reviewed with no fragments
  done: false
- title: Re-reading and marking the stale fragment leaves nothing in stale, every line reviewed in coverage, and both records in the sidecar
  done: false
- title: A whole region cut and pasted elsewhere in the file still reports moved, not stale
  done: false
- title: stale --json keeps today's keys per item; regions --json returns one item per fragment with the original record's provenance and moved per fragment
  done: false
- title: A record its recorded commit does not confirm, and a store with no git, report whole-region stale as today
  done: false
- title: Emacs ERT integration tests pass unchanged
  done: false
deps:
- lgu-01m29hdfncjk
---

## Description

The tracer bullet for per-hunk staleness (spec: lgu-01m29h4g9n4s, ADR-0018). A review record is confirmed against its recorded commit: the region as it was in that commit's file must hash to the record's content hash. Once confirmed, hunks fully inside the projected region split the record into fragments: the hunk's new-side lines are stale, lines between hunks are reviewed at their shifted position, and each fragment is moved when its own offset is nonzero. Covers edit in place, edit that grows, edit that shrinks, and pure insertion. The anchoring ladder keeps its order: byte-identical is reviewed, projection plus hash next, the whole-region moved-block search next, and only where today returns whole-region stale does fragmenting run.

Consumers: per-path resolution yields one range per fragment; the existing line-level rule that any reviewed fragment wins over stale is unchanged. `stale` prints one item per stale fragment, sorted by path and start, and drops fragments a reviewed fragment covers. `regions` returns one item per fragment carrying the original record's provenance; `status`, `coverage` and `next` follow from the line-level state. The store, schema 4, record shape and signatures do not change; ADR-0013 supersede rule unchanged.

Fallbacks: a record its recorded commit does not confirm, and a store with no git, report whole-region stale exactly as today. Deletion seams, boundary-straddling hunks, whitespace and the dirty-tree forward search are separate tickets; until they land, a hunk that is a pure deletion or straddles the boundary keeps whole-region staleness.
