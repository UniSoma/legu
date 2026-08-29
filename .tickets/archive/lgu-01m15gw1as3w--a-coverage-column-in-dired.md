---
id: lgu-01m15gw1as3w
title: A coverage column in dired
status: closed
type: feature
priority: 2
mode: afk
created: '2026-08-29T01:06:45.209694019Z'
updated: '2026-08-29T01:23:53.710943560Z'
closed: '2026-08-29T01:23:53.710943560Z'
acceptance:
- title: 'In a dired buffer under a repository with a .review store, global-legu-mode enables legu-dired-mode and every eligible file and every directory with eligible files beneath it shows a fixed-width column before the filename: reviewed percent (floor) and stale percent (ceiling, blank when zero), e.g. ''72% 3%''; legu-dired-column nil turns it off'
  done: true
- title: Directory numbers are line-weighted sums over the eligible files beneath; ineligible files and directories with no eligible file show '—'; the column is blank only when there is no snapshot yet, and opening the dired buffer then requests one
  done: true
- title: A file whose mtime is newer than the snapshot shows its numbers with a '?' suffix, as the lighter does, and a directory inherits '?' from any such file; the column re-renders when a snapshot lands, without shelling out at render time
  done: true
- title: Inserted subdirectories and dired-subtree sections get the column too; the column survives dired-hide-details-mode; TRAMP and dirvish buffers are left blank
  done: true
- title: 'Faces: default for reviewed, legu-stale for a non-zero stale percent, dimmed for ''?'' and ''—''; no colour thresholds; no mark/forget/ticket actions from dired'
  done: true
- title: The mode-line lighter uses floor instead of round for its reviewed percent; ert tests cover the directory aggregation and the formatting rules; CONTEXT.md's Coverage entry reflects per-directory and per-file coverage and the two-numbers-plus-remainder display
  done: true
external_refs:
- git:37cc7ecabce7733f3f3ad0e1e4c1406a8a025c5d
---

## Description

Show review coverage in dired: a column before the filename with reviewed and stale percentages for each eligible file and, line-weighted, for each directory containing eligible files. Unreviewed is the remainder, per the Coverage entry in CONTEXT.md.

Everything renders from the cached snapshot, which already carries per-file rows for every eligible file; directory numbers are prefix sums over those rows. Rendering never runs the CLI. Freshness follows ADR 0011: numbers the snapshot cannot vouch for (file newer than the snapshot) are suffixed '?' until the debounced refresh replaces them.

Design decisions, all settled in a grilling session:
- Two numbers, not one and not three: reviewed (floor) and stale (ceiling, blank at zero). Both rounding errors point at remaining work, never away from it. The lighter moves to floor for consistency.
- '—' for ineligible; blank only for 'no snapshot yet'.
- Column sits before the filename so it stays a column regardless of name length and survives hide-details.
- Enabled automatically by global-legu-mode under a store-bearing root, off via a defcustom.
- Read-only. Marking a directory unopened is the claim legu-list-mark guards with a confirmation; it gets its own ticket if wanted.
- Out of scope: dirvish attribute, TRAMP dired.

## Notes

**2026-08-29T01:23:53.710943560Z**

legu-dired-mode in emacs/legu-dired.el: a fixed-width column before the filename with reviewed (floor) and stale (ceiling, blank at zero) percents per eligible file and, line-weighted, per directory; ? for files newer than the snapshot and the directories above them; dash for ineligible; blank until the first snapshot, which opening the buffer requests. Rendered from the cached snapshot only, redrawn when one lands, hooked into inserted subdirs, dired-subtree (untested here, package not installed) and hide-details; TRAMP and dirvish skipped. Lighter floors its percent. CONTEXT.md Coverage entry updated. 12 ERT tests.
