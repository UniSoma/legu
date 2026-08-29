---
id: lgu-01m147mc4c8x
title: Re-marking a region should supersede the record it overlaps
status: closed
type: bug
priority: 2
mode: afk
created: '2026-08-28T13:06:02.508896759Z'
updated: '2026-08-29T01:48:29.711806941Z'
closed: '2026-08-29T01:48:29.711806941Z'
acceptance:
- title: Marking a region that fully contains an existing record leaves exactly one record behind
  done: true
- title: The chosen overlap rule is stated in the README, with the reasoning for it
  done: true
- title: '`legu stale` no longer reports a region that has been re-read at a drifted range'
  done: true
- title: 'Ticket references anchored inside the re-marked region are untouched: they are independent anchors, not fields of the retired record'
  done: true
links:
- lgu-01m14z6pw14r
tags:
- settled
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

A whole-file mark on a text file has the same defect: `region-of` turns it into
a `1-N` range, not an opaque region, so it retires nothing either.

Marking a region should retire the review records it now fully contains. The
rule and its reasoning are ADR-0013
(docs/adr/0013-a-mark-supersedes-only-what-it-contains.md); the glossary terms
**Supersede** and **Ghost** in CONTEXT.md match it.

### Decisions

- Containment only, per ADR-0013: a mark retires every review record whose
  current anchor lies fully inside the marked range. Partial overlap retires
  nothing; the old record stays and `stale` keeps naming its whole range.
- Containment is judged at the record's *resolved* location (`resolve-region`),
  never its stored range — the same comparison `same-region?` already makes.
  Records in other sidecars that resolve into the marked file are retired as
  `purge!` does today; a `:missing` record is never inside a region and is
  untouched.
- The rule applies to review records only. `legu note`/`ticket` keeps
  exact-place supersede for a same-id reference, so the containment test is a
  mark-only predicate beside `superseded?`; `superseded?` as used for tickets
  does not change.
- `cmd-stale` does not change: retiring the record is what makes the region
  leave the list.
- The `carried`/`:notes` mechanism in `purge!` is left alone; lgu-01m14z6pw14r
  deletes it. Whichever ticket lands second rebases over the other.
- README: the rule goes into the paragraph that describes what a mark stores,
  one sentence of rule and one of reason, pointing at ADR-0013. The known-limit
  bullet about exact-place supersede is deleted; the bullet about overlapping
  ranges is reworded to say a partly re-read region survives as its own record.
- The behaviour test is an ert integration test in `emacs/legu-tests.el`, beside
  `legu-test-integration-remark-of-a-stale-region-clears-it`, whose comment
  ("supersedes a record only where it currently sits") is updated to match.

## Notes

**2026-08-28T19:58:06.718545868Z**

The description's 'carrying their ticket references onto the new record' is superseded by ADR-0012: the per-record notes field is gone (see lgu-01m14z6pw14r). Ticket references are independent anchors and need no carrying.

**2026-08-29T01:48:29.711806941Z**

A mark retires every review record it fully contains (ADR-0013); partial overlap leaves the record, opaque records go only with a whole-file mark, ticket references untouched.
