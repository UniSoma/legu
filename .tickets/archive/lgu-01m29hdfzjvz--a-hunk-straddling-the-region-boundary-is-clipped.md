---
id: lgu-01m29hdfzjvz
title: A hunk straddling the region boundary is clipped by prefix
status: closed
type: task
priority: 1
mode: afk
created: '2026-09-12T00:48:56.818186085Z'
updated: '2026-09-12T03:12:36.121873040Z'
closed: '2026-09-12T03:12:36.121873040Z'
parent: lgu-01m29h4g9n4s
tags:
- ready-for-agent
- per-hunk-staleness
acceptance:
- title: An edit at 60-80 against a region 73-150 with 1-72 unreviewed reports stale only from the clipped start, and 1-72 stays unreviewed
  done: true
- title: An edit crossing the region's end reports stale only up to the region's projected end
  done: true
- title: A straddling hunk that shrank below the region's offset into it leaves one seam line
  done: true
- title: Two adjacent records crossed by one hunk each report their own clipped stale fragment and together tile the hunk
  done: true
deps:
- lgu-01m29hdfrne0
---

## Description

Per-hunk staleness, boundary rule (spec: lgu-01m29h4g9n4s, ADR-0018). A hunk that crosses the region's start or end carries no line-to-line mapping inside it. Its stale fragment is clipped by prefix: it starts at the hunk's new start plus the region's offset into the hunk's old lines, and ends at the hunk's new end or the region's projected end, whichever the record covers; a hunk that shrank below that offset leaves a seam line. The record never claims a line it did not cover, so a neighbouring unreviewed range stays unreviewed.

## Notes

**2026-09-12T03:12:36.121873040Z**

A hunk crossing the region's boundary is clipped by prefix: its stale fragment starts as far into the hunk's new lines as the region started into its old ones and ends at the region's projected end or the hunk's last line, whichever comes first, so lines nobody read stay unreviewed rather than becoming stale. A hunk that shrank below that offset leaves one seam line through the same seam rule lgu-01m29hdfw791 defined, generalised in place rather than duplicated. Two adjacent records crossed by one hunk tile it between them with no line claimed twice and none dropped.

## Notes

A hunk crossing the region boundary is clipped by prefix, so a record never claims a line it did not cover, and one that shrank below the offset takes the seam. Landed in 319724f.
