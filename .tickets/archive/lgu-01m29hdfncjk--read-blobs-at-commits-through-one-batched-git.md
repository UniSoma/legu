---
id: lgu-01m29hdfncjk
title: Read blobs at commits through one batched git process
status: closed
type: task
priority: 1
mode: afk
created: '2026-09-12T00:48:56.491931192Z'
updated: '2026-09-12T02:22:31.058153608Z'
closed: '2026-09-12T02:22:31.058153608Z'
parent: lgu-01m29h4g9n4s
tags:
- ready-for-agent
- per-hunk-staleness
acceptance:
- title: Reading a file at a commit goes through one batched git process per run, cached per commit and path
  done: true
- title: The full CLI suite and ERT pass with no change in any reported state
  done: true
- title: A test with several changed files across two commits anchors every record correctly through the batched reader
  done: true
---

## Description

Prefactor for the per-hunk staleness feature (spec: lgu-01m29h4g9n4s), with no behaviour change. Today the text of a file at a commit is read with one `git show` process per call. The fragment step that follows needs that text for every changed file, so it must come from one `git cat-file --batch` process per run, fed the commit:path pairs it needs and cached per pair, in the same shape as hunks already come from one `git diff` per commit. Anchoring's results are unchanged; the existing suite is the proof, plus one test with several changed files across two commits that exercises the batched reader.

## Notes

**2026-09-12T02:22:31.058153608Z**

read-at-commit now reads from a run-scoped cache filled by one git cat-file --batch over every [commit path] pair the records cite, prefetched beside the existing hunk fetch. A pair nobody prefetched still pays for a batch of its own, so no caller's answer depends on having been prefetched. Pinned by a GIT_TRACE case asserting one cat-file and zero git show, a framing case over an empty, a missing and a header-shaped blob, and a case that reads one path at two commits with an edit inside each record.

## Notes

Blobs at commits now come from one batched git cat-file, cached per commit and path, prefetched beside the hunks. Landed in 1e1d454 with the tracer bullet that needed it.
