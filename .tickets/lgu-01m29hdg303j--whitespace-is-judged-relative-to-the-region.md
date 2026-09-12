---
id: lgu-01m29hdg303j
title: Whitespace is judged relative to the region
status: open
type: task
priority: 1
mode: afk
created: '2026-09-12T00:48:56.928888853Z'
updated: '2026-09-12T00:48:57.600133353Z'
parent: lgu-01m29h4g9n4s
tags:
- ready-for-agent
- per-hunk-staleness
acceptance:
- title: A whole-block reindent inside a region reports the block reviewed, alone and beside a real edit in the same file
  done: false
- title: Wrapping a block in a new if reports the inserted line stale and the shifted block reviewed
  done: false
- title: One line dedented out of a block, with no other character changed, reports that line stale
  done: false
- title: Trailing-whitespace edits, a CRLF flip and a trailing-newline change report the region reviewed
  done: false
- title: Tab-to-space conversion reports stale
  done: false
- title: A record no commit confirms keeps today's trim-only behaviour
  done: false
deps:
- lgu-01m29hdfrne0
---

## Description

Per-hunk staleness, whitespace rules (spec: lgu-01m29h4g9n4s, ADR-0018 and ADR-0019). Once a record is confirmed at a commit, anchoring holds the exact text that was read, so whitespace is judged between old text and new text at anchoring time and the stored hash keeps ADR-0003's trim. Per hunk: old and new lines equal after trailing-whitespace trim are not a change and stay reviewed. Then one region-level check: the old text with only the strict hunks applied must equal the new text after removing the leading whitespace common to every line of each and trimming line ends; if not, the whitespace-equal hunks that broke the offsets are stale too. So a block reindented together stays reviewed, and a line moved to another indentation level goes stale with no other character touched. Tab-to-space conversion changes relative offsets and is stale, as ADR-0003 already treats reformats. A record no commit confirms falls back to the trim alone.
