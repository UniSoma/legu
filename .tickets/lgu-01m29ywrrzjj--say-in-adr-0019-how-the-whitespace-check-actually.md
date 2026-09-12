---
id: lgu-01m29ywrrzjj
title: Say in ADR-0019 how the whitespace check actually runs
status: open
type: task
priority: 2
mode: hitl
created: '2026-09-12T04:44:28.831212383Z'
updated: '2026-09-12T04:44:28.831212383Z'
---

## Description

ADR-0019 specifies the mechanism, not just the goal:

> the fragment step judges hunks strictly on trailing whitespace, then checks
> once that the old text with only the strict hunks applied is
> region-equivalent to the new text; if it is not, the whitespace hunks that
> broke the offsets are stale too.

Taken literally that cannot satisfy lgu-01m29hdg303j's criteria 1, 2 and 3
together, which the phase's spec review confirmed by building two variants of
`legu` and running them:

- Literal (git hunks, one whole-region check): wrapping a block reports the
  whole wrapped range stale, and a lone dedent reports the whole region stale.
  Fails criteria 2 and 3.
- Whole-region check plus the shipped `shrink-hunk`: the wrap passes, the lone
  dedent still reports the whole region stale. Fails criterion 3.
- Shipped (the question put to each run of lines the strict hunks leave
  between them): all three pass.

The shipped code therefore deviates from the ADR's sentence in three ways, all
of which the ADR should record:

1. **Per run, not once.** The equivalence question goes to each run of lines
   between the strict hunks, not once to the whole region. Only this
   distinguishes a wrapped block from a lone dedent.
2. **`shrink-hunk` is not in the ADR at all.** `git diff -U0` emits an
   insertion and the reindent it causes as one hunk, so the hunks have to be
   shrunk to the lines their two sides do not share before anything else. The
   literal algorithm fails criterion 2 on hunk granularity before any
   equivalence question is reached.
3. **Blank lines are excluded from the common leading run**, where the ADR
   says "the leading whitespace common to every line". A blank line shares no
   indentation; including it would collapse the common run to nothing.

Also worth recording: a block wrapped mid-region, with unshifted lines still
inside the region after it, reports the block stale, because that run is not
one read. That is defensible under the ADR's own principle — those lines did
change offset relative to the ones left behind — but the ADR's unqualified
sentence "Wrapping a block in a new `def` or `if` ... the block stays
reviewed" does not say so.

The code is believed right and the ADR incomplete, so this is an ADR edit, not
a code change. Raised by the spec review of the phase that landed
lgu-01m29hdg303j.
