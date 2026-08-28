---
id: lgu-01m147n36kqb
title: Paint a renamed file's review state without waiting for a snapshot
status: open
type: task
priority: 2
mode: hitl
created: '2026-08-28T13:06:26.131588888Z'
updated: '2026-08-28T13:06:26.228359222Z'
acceptance:
- title: Opening a file whose regions were read under a previous name shows their state without waiting for a repository snapshot
  done: false
- title: The test that currently asserts the blind spot is flipped to assert the fix
  done: false
- title: The README's known-limits entry for renames is removed or rewritten to whatever limit remains
  done: false
- title: A copy still does not inherit the original's marks
  done: false
deps:
- lgu-01m147n30cnf
---

## Description

The Emacs package paints a file the instant it is opened, with no subprocess, by
reading that file's sidecar and hashing the file. Sidecars are keyed by the path
a region was read at, so after a rename the sidecar is under the *old* path: the
file paints as entirely unread until the next repository snapshot lands and
repairs the picture.

The CLI follows renames correctly — this is a gap in what a client can work out
locally, not in the anchoring.

Whichever way it is closed, the fix belongs behind the per-file query rather
than in a second implementation of rename-following in the client.

There is a test asserting the current behaviour, named as the documented limit;
closing this should flip it rather than delete it.

Open question to settle first: whether the per-file query answers by current
path (the CLI already knows the rename) or whether the store should record a
forwarding pointer when a mark relocates. The first is less state and less to go
wrong; the second is what makes the answer available without running anything.
