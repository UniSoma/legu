---
id: lgu-01m29hdg6d6r
title: A mark made on a dirty working tree still fragments
status: closed
type: task
priority: 1
mode: afk
created: '2026-09-12T00:48:57.037459468Z'
updated: '2026-09-12T04:46:44.589265922Z'
closed: '2026-09-12T04:46:44.589265922Z'
parent: lgu-01m29h4g9n4s
tags:
- ready-for-agent
- per-hunk-staleness
acceptance:
- title: 'Mark a file with uncommitted edits, commit, edit inside the region: the record fragments as if marked at that commit'
  done: true
- title: 'Mark, then make two more commits to the file before editing: the first confirming commit is used'
  done: true
- title: A record citing an unreachable commit reports whole-region stale as today
  done: true
- title: The search is capped and does not walk the whole history of the path
  done: true
deps:
- lgu-01m29hdfrne0
---

## Description

Per-hunk staleness, confirmation forward search (spec: lgu-01m29h4g9n4s, ADR-0018). A mark records HEAD as its commit but hashes the working tree, so a mark on uncommitted code cites a commit whose text it did not read and the recorded commit cannot confirm it. When that happens, the later commits that touched the path are tried in order, capped at a small number, and the first that confirms is the commit diffed against, its blob read through the batched reader. A commit that no longer exists cannot be searched forward from and keeps the whole-region fallback. Without this the feature is silently absent for anyone marking from the editor mid-edit.

## Notes

**2026-09-12T04:46:44.589265922Z**

A mark taken on a dirty working tree cites a commit whose text it never read. When the cited commit does not confirm the record's hash, the commits after it that touched the path are tried oldest first and the first that confirms is diffed against instead, so the record fragments as if marked at that commit (ADR-0018). The walk is capped at five commits, the candidates are gathered for every record before any git call the way prefetch! gathers the rest, and a record no commit confirms still reports whole-region stale.
