---
id: lgu-01m222gxgz0p
title: Count an empty file as one eligible line
status: closed
type: bug
priority: 2
mode: afk
created: '2026-09-09T03:13:59.326984406Z'
updated: '2026-09-09T03:14:39.398904207Z'
closed: '2026-09-09T03:14:39.398904207Z'
acceptance:
- title: An unmarked empty file is one unreviewed line in status, coverage and next; a marked one is one reviewed line.
  done: true
external_refs:
- git:54319e31169bbd128e4992a0b40a975cc6811464
---

## Description

CONTEXT.md says an opaque region, a whole binary or empty file, counts as one
line, and `legu regions` reports an empty file as one opaque line. But
`eligible-files` counts a text file's lines, so an empty file has zero: it
contributes nothing to `coverage` or `status` whether marked or not, `next`
never queues it, and it only enters the numbers once it gains content and its
record goes stale.

Make a text file count at least one line in `eligible-files`. Binary files
already work this way and the coverage code already maps an opaque record to
line one, so nothing else changes. Emacs derives its numbers from `status`
rows and follows.

## Notes

**2026-09-09T03:14:39.398904207Z**

eligible-files counts a text file as at least one line, so an empty file is one unreviewed line until marked and one reviewed line after, in status, coverage and next. README notes it; a new ERT test pins it.
