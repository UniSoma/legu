---
id: lgu-01m29hdfw791
title: A deletion leaves one stale line at the seam
status: open
type: task
priority: 1
mode: afk
created: '2026-09-12T00:48:56.711695623Z'
updated: '2026-09-12T00:48:57.371705455Z'
parent: lgu-01m29h4g9n4s
tags:
- ready-for-agent
- per-hunk-staleness
acceptance:
- title: Deleting 73-97 inside a 150-line record reports stale at line 73 only, with 1-72 reviewed and 74-125 reviewed and moved
  done: false
- title: Deleting the last lines of a region puts the seam on the last remaining line of the region
  done: false
- title: Deleting every line of a region reports stale at the clamped range reported today
  done: false
- title: Cutting part of a region and pasting it elsewhere reports a seam where it was and the pasted block unreviewed
  done: false
deps:
- lgu-01m29hdfrne0
---

## Description

Per-hunk staleness, deletion rule (spec: lgu-01m29h4g9n4s, ADR-0018). A pure deletion has no new lines to point at, so its seam is the line after it when that line is still inside the region, else the line before it. A record whose every line was deleted has no seam and reports stale at the clamped range the code already produces. A part of a region cut and pasted elsewhere in the file is the same case seen from the other side: a seam where it was, and the pasted block counts unreviewed where it landed, since the moved-block search looks for the whole region only.
