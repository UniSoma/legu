---
id: lgu-01m147mc7bd4
title: Order the reading queue by commit co-change frequency
status: open
type: feature
priority: 3
mode: hitl
created: '2026-08-28T13:06:02.603542986Z'
updated: '2026-08-28T13:06:02.603542986Z'
acceptance:
- title: '`next` accepts a flag selecting co-change ordering; directory order remains the default'
  done: false
- title: The co-change computation is measured on a real multi-year repository and the number is recorded on the ticket
  done: false
- title: The ordering uses only git history, with no language knowledge
  done: false
- title: README documents both orderings and when each helps
  done: false
---

## Description

`next` orders by directory, which is the ordering the spec names first and a
fine default: it keeps a reader inside one part of the tree.

The spec names a second generic ordering — commit co-change frequency — and it
answers a different question: what should I read next *given what I have already
read*, surfacing the files that change alongside the ones already covered. Both
are language-agnostic, which is the constraint that rules out dependency
analysis.

This is an ordering, not a recommendation engine. Directory order stays the
default; the alternative goes behind a flag.

Open question to settle first, and worth prototyping on a real repository before
committing to it: what the co-change signal is computed over (all history, or a
recent window), and how expensive that is on a two-year history — the ordering
is worthless if `next` stops being instant.
