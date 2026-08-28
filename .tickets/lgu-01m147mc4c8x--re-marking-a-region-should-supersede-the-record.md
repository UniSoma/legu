---
id: lgu-01m147mc4c8x
title: Re-marking a region should supersede the record it overlaps
status: open
type: bug
priority: 2
mode: afk
created: '2026-08-28T13:06:02.508896759Z'
updated: '2026-08-28T13:06:02.508896759Z'
acceptance:
- title: Marking a region that fully contains an existing record leaves exactly one record behind
  done: false
- title: Ticket references on a retired record are carried onto the new one
  done: false
- title: The chosen overlap rule is stated in the README, with the reasoning for it
  done: false
- title: '`legu stale` no longer reports a region that has been re-read at a drifted range'
  done: false
---

## Description

A mark supersedes a stored record only when that record currently resolves to
*exactly* the same place. Read a region, let the code drift so it projects to a
slightly different range, then re-read and mark what you actually read: you now
have two records. The old one keeps reporting in `stale` forever, and the only
way out is to know that `forget` exists and to run it by hand.

The workaround is documented — re-mark the exact range `stale` prints — but it
asks the user to type a range legu already knows, and the failure is silent
until the stale list stops shrinking.

Marking a region should retire the records it overlaps, carrying their ticket
references onto the new record the way an exact supersede already does.

Worth deciding explicitly, and recording in the ticket: whether *any* overlap
retires the old record or only containment, and what happens to the part of an
old region that the new mark does not cover. The conservative reading — a
partly re-read region is not a read region — argues for retiring only records
the new mark fully contains, and leaving the rest to be re-read.
