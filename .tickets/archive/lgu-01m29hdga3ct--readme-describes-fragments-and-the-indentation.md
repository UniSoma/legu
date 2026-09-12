---
id: lgu-01m29hdga3ct
title: README describes fragments and the indentation rule
status: closed
type: task
priority: 2
mode: afk
created: '2026-09-12T00:48:57.155231479Z'
updated: '2026-09-12T04:46:44.692456762Z'
closed: '2026-09-12T04:46:44.692456762Z'
parent: lgu-01m29h4g9n4s
tags:
- ready-for-agent
- per-hunk-staleness
acceptance:
- title: The staleness section describes fragments, the seam, boundary clipping and relative indentation
  done: true
- title: The guidance paragraph gives region size its new reason
  done: true
- title: The known limit about a partly re-marked record's whole range is gone
  done: true
- title: bb lint passes
  done: true
deps:
- lgu-01m29hdfw791
- lgu-01m29hdfzjvz
- lgu-01m29hdg303j
- lgu-01m29hdg6d6r
---

## Description

Docs for per-hunk staleness (spec: lgu-01m29h4g9n4s). The staleness section of the README describes fragments, the deletion seam, the boundary clipping and the region-relative indentation rule; the guidance paragraph says region size bounds what one record vouches for rather than how much goes stale; the known limit about `stale` naming a partly re-marked record's whole range is removed. Written against the shipped behaviour, so it lands last.

## Notes

**2026-09-12T04:46:44.692456762Z**

The README's staleness section now describes fragments, the seam, boundary clipping and indentation judged relative to the region, and says what regions --json returns per fragment and that a ticket reference is never fragmented. The guidance to mark what you can hold in your head keeps its place with its new reason: region size no longer affects staleness, but it still bounds what one record vouches for. The known limit about a partly re-marked record's whole range is gone, having been reproduced as fixed first.
