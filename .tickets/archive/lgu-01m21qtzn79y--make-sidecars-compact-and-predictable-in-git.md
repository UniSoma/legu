---
id: lgu-01m21qtzn79y
title: Make sidecars compact and predictable in Git
status: closed
type: task
priority: 2
mode: afk
created: '2026-09-09T00:07:14.855591662Z'
updated: '2026-09-09T03:05:20.867052635Z'
closed: '2026-09-09T03:05:20.867052635Z'
acceptance:
- title: CLI mark, ticket, and forget operations produce fixed-layout, deterministic EDN. Identical logical state produces identical bytes, including ties in region ordering.
  done: true
- title: Sidecars omit the redundant source path. Opaque regions omit line boundaries and content hash while retaining the opaque flag and full file hash. Text regions retain both full hashes.
  done: true
- title: Review records retain commit, reviewer, timestamp, and all required content evidence. Ticket references retain their IDs and anchoring evidence. Both empty collection sections remain explicit; an entirely empty sidecar is removed.
  done: true
- title: The CLI and Emacs read the new representation and agree on review evidence. Emacs retains its existing restriction on locally confirming review state. No backward-compatibility reader or migration is introduced.
  done: true
- title: Integration tests cover marking, superseding, forgetting, and ticket references through persisted sidecars and their consumers, including text, binary, empty, moved, stale, and missing regions.
  done: true
- title: Git diff fixtures verify that adding or removing a record leaves surviving records unchanged. Test that separate edits merge where expected and competing edits remain explicit conflicts.
  done: true
- title: Tests preserve rename handling, the refusal to follow copies, and superseding only contained review records. Documentation states the new layout and unchanged review semantics.
  done: true
external_refs:
- git:755cf4b1a2b030e6dac227cda755a0e6ada1c837
---

## Description

Keep one EDN sidecar per source file. Make changes to the committed store easy to inspect in Git. Keep each review record self-contained rather than grouping repeated evidence.

Use a fixed field layout and descriptive keys. Put region boundaries on one line and reviewer and timestamp on another. Give each full hash and commit its own line. Put collection delimiters on separate lines. Do not use width-dependent wrapping, commas, positional tuples, shortened hashes, or generated record IDs.

Derive the source path from the sidecar location. For opaque regions, keep the opaque flag and file hash. Omit their nil line boundaries and duplicate content hash. Keep both hashes for text regions. Keep empty review-record and ticket-reference sections. Remove an empty sidecar as before.

Sort review records and ticket references by region, with deterministic tie-breakers from their remaining persisted fields. Preserve evidence and the current supersede and forget semantics. Do not merge overlapping review records or discard stale or missing review records automatically.

Update CLI writes, CLI reads, Emacs reads, tests, and documentation together. There are no external users, so no migration or legacy reader is required. No performance redesign belongs in this ticket.

Evidence: throwaway branch prototype/review-store-encoding, commit 2142e22d57db31d871af665916aab59c29df0fcd. It retains the encoding experiment, scripts, raw results, and Git patches.

## Notes

**2026-09-09T03:05:20.867052635Z**

Sidecars are schema 2 in a fixed layout: region on one line, reviewer or ticket with timestamp on the next, commit and each full hash on their own lines, delimiters on their own lines, no source path, opaque records with only the opaque flag and file hash. Records sort by region then every other field, so identical state is identical bytes. CLI and Emacs read only schema 2; older schemas are refused rather than migrated. Ten ERT tests cover layout, determinism, every record kind through the consumers, git numstat on add and forget, clean merges of separate and adjacent edits, and an explicit conflict on competing edits. README storage section and ADR-0014 document the layout.
