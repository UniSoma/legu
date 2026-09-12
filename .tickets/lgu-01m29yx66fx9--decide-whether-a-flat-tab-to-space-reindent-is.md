---
id: lgu-01m29yx66fx9
title: Decide whether a flat tab-to-space reindent is stale
status: open
type: task
priority: 1
mode: hitl
created: '2026-09-12T04:44:42.575365352Z'
updated: '2026-09-12T04:44:42.575365352Z'
---

## Description

ADR-0019 holds two sentences that collide, and the collision is reachable.

The rule:

> Two texts are the same read when, after removing the leading whitespace
> common to every line of each, they trim equal at the end of each line.

The consequence it claims:

> Tabs converted to spaces change relative offsets and go stale; that is a
> reformat, and ADR-0003 already calls reformats stale.

The second only follows when the region holds more than one indentation
level. Where every line of the region sits at the same level, converting tabs
to spaces is a uniform shift, which the rule calls the same read — the very
thing the rule exists to allow, since a whole-block reindent is the same
shape.

Repro, and why it matters:

    all:
    <TAB>echo one
    <TAB>echo two
    <TAB>echo three

`legu mark Makefile:2-4`, then convert the three tabs to four spaces each.
`legu regions Makefile` reports the region **reviewed**. The Makefile no
longer runs: make requires a tab. A semantic break went unreported.

lgu-01m29hdg303j's criterion 5 ("Tab-to-space conversion reports stale") is
unqualified and so is the ADR sentence; the shipped code follows the rule
sentence instead. The criterion was narrowed at close to describe what
shipped, with this ticket named as the open question.

The two cannot both hold as written: "a whole-block reindent stays reviewed"
and "a flat tab-to-space conversion is stale" are the same shape — a uniform
change to every line's leading whitespace. Deciding between them is the
ticket. Options seen so far:

1. Accept it: the rule wins, and ADR-0019's tab sentence is narrowed to
   regions holding more than one level. Cheapest, and leaves the Makefile
   case unreported.
2. Make a change in the *kind* of the common leading whitespace a change,
   even when stripping it leaves the rest equal. Catches the Makefile, and
   needs checking against a block reindented from tabs to tabs.
3. Treat it as ADR-0003's reformat rule rather than ADR-0019's layout rule
   and compare the raw leading runs for kind before the relative test.

Raised by the spec review of the phase that landed lgu-01m29hdg303j, which
verified the repro against the built CLI.
