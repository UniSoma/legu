---
id: lgu-01m29hdga3ct
title: README describes fragments and the indentation rule
status: open
type: task
priority: 2
mode: afk
created: '2026-09-12T00:48:57.155231479Z'
updated: '2026-09-12T00:48:58.190010583Z'
parent: lgu-01m29h4g9n4s
tags:
- ready-for-agent
- per-hunk-staleness
acceptance:
- title: The staleness section describes fragments, the seam, boundary clipping and relative indentation
  done: false
- title: The guidance paragraph gives region size its new reason
  done: false
- title: The known limit about a partly re-marked record's whole range is gone
  done: false
- title: bb lint passes
  done: false
deps:
- lgu-01m29hdfw791
- lgu-01m29hdfzjvz
- lgu-01m29hdg303j
- lgu-01m29hdg6d6r
---

## Description

Docs for per-hunk staleness (spec: lgu-01m29h4g9n4s). The staleness section of the README describes fragments, the deletion seam, the boundary clipping and the region-relative indentation rule; the guidance paragraph says region size bounds what one record vouches for rather than how much goes stale; the known limit about `stale` naming a partly re-marked record's whole range is removed. Written against the shipped behaviour, so it lands last.
