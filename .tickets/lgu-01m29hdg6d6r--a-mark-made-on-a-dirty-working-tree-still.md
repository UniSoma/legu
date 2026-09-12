---
id: lgu-01m29hdg6d6r
title: A mark made on a dirty working tree still fragments
status: open
type: task
priority: 1
mode: afk
created: '2026-09-12T00:48:57.037459468Z'
updated: '2026-09-12T00:48:57.714354544Z'
parent: lgu-01m29h4g9n4s
tags:
- ready-for-agent
- per-hunk-staleness
acceptance:
- title: 'Mark a file with uncommitted edits, commit, edit inside the region: the record fragments as if marked at that commit'
  done: false
- title: 'Mark, then make two more commits to the file before editing: the first confirming commit is used'
  done: false
- title: A record citing an unreachable commit reports whole-region stale as today
  done: false
- title: The search is capped and does not walk the whole history of the path
  done: false
deps:
- lgu-01m29hdfrne0
---

## Description

Per-hunk staleness, confirmation forward search (spec: lgu-01m29h4g9n4s, ADR-0018). A mark records HEAD as its commit but hashes the working tree, so a mark on uncommitted code cites a commit whose text it did not read and the recorded commit cannot confirm it. When that happens, the later commits that touched the path are tried in order, capped at a small number, and the first that confirms is the commit diffed against, its blob read through the batched reader. A commit that no longer exists cannot be searched forward from and keeps the whole-region fallback. Without this the feature is silently absent for anyone marking from the editor mid-edit.
