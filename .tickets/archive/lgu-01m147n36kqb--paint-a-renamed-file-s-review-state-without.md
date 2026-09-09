---
id: lgu-01m147n36kqb
title: Paint a renamed file's review state from a per-file query, without waiting for a snapshot
status: closed
type: feature
priority: 2
mode: afk
created: '2026-08-28T13:06:26.131588888Z'
updated: '2026-09-09T02:20:32.176843081Z'
closed: '2026-09-09T02:20:32.176843081Z'
acceptance:
- title: The test that currently asserts the blind spot is flipped to assert the fix
  done: true
- title: Opening a file whose regions were read under a previous name paints their state at their current anchors before any repository snapshot has run
  done: true
- title: A file whose sidecar confirms every record paints with no subprocess; a file the local pass cannot account for runs one asynchronous per-file query and never blocks Emacs
  done: true
- title: A per-file answer is dropped when the buffer content changed since the request or a newer answer or trusted snapshot supersedes it, and it may paint stale where the CLI says so
  done: true
- title: The Emacs README's known-limits entry for renames is removed and its tier description names the per-file query
  done: true
- title: A copy still does not inherit the original's marks, through the painting path
  done: true
deps:
- lgu-01m147n30cnf
---

## Description

Opening a file paints from its sidecar and a file hash instantly, as today. When that local pass cannot account for the file (no sidecar at its current path, or a record whose hash no longer matches) and no trusted snapshot already covers it, the package runs `legu regions` for that one file asynchronously and paints from the answer: reviewed and stale ranges and ticket lines at their current anchors. A file whose sidecar confirms every record still runs no subprocess.

The per-file answer sits between the sidecar and the repository snapshot. It comes from the CLI, so it may pronounce stale, moved or missing, which local computation still never does. An answer is discarded when the buffer content changed since it was requested, or when a newer per-file answer or a trusted snapshot for that buffer supersedes it, the same guard `legu-describe-region` uses. An incomplete answer paints what was resolved and keeps the unverified indicator, matching the corrupt-sidecar behaviour. The same query runs after save and revert under the same condition. Nothing blocks Emacs.

A copy still inherits nothing: the CLI refuses to follow copies, and the painting path must show that. Flip `legu-test-integration-rename-is-the-documented-tier0-blind-spot` to assert the renamed file paints its reviewed lines before any snapshot has run. Remove the rename entry from the Emacs README's known limits and rewrite its tier description to name the per-file query and the one case that still runs nothing.
