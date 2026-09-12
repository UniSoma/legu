---
id: lgu-01m29sm9600c
title: A swallowed region falls back to a stale range it never read
status: open
type: task
priority: 2
mode: hitl
created: '2026-09-12T03:12:27.840477614Z'
updated: '2026-09-12T03:12:27.840477614Z'
---

## Description

ADR-0018 sanctions the clamped whole-region fallback for "A record whose
every line was deleted". `no-seam?` applies it more widely: to any region a
hunk swallowed, including one merely replaced. The record then reports stale
at the range it was read at, which may cover lines a neighbouring record
holds reviewed, against ADR-0018's "The record never claims a line it did
not cover".

Repro: records at 1-40, 41-70 and 71-150 of a 150-line file, then one hunk
replacing old 30-100 with 8 lines. Record 41-70 is swallowed but not
deleted. It falls back to stale 41-70, which overlaps record 71-150's
reviewed 39-87.

Both candidate seam lines lie outside the swallowed region, so there is no
seam for `seam-of` to fall on, and the fallback is a defensible resolution
of two ADR rules in conflict. But the ADR does not cover the case, so the
decision has not been made. Deciding it is the first half of this ticket:
either ADR-0018 is amended to say what a swallowed region reports, or the
fallback is narrowed to the all-deleted case the ADR already names and the
swallowed case gets an answer of its own.

Found by the spec review of the phase that landed lgu-01m29hdfw791 and
lgu-01m29hdfzjvz.
