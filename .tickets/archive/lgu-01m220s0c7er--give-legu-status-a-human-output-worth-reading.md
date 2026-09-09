---
id: lgu-01m220s0c7er
title: Give legu status a human output worth reading
status: closed
type: task
priority: 2
mode: afk
created: '2026-09-09T02:43:27.239567878Z'
updated: '2026-09-09T02:46:15.210891606Z'
closed: '2026-09-09T02:46:15.210891606Z'
acceptance:
- title: Header shows the three numbers for the scope, as three rows, with bars
  done: true
- title: Path column fits its content; deep paths no longer push numbers off the grid
  done: true
- title: --gaps hides files read in full
  done: true
- title: --json keeps files[] and tickets[] unchanged and adds coverage
  done: true
- title: ERT integration tests pass unchanged
  done: true
- title: README documents --gaps
  done: true
---

## Description

`legu status` prints a flat `FILE REV STALE TOTAL REVIEWED` table with a fixed 52-column path field that overflows on deep paths, no header for the scope, no unreviewed column, and `-` for empty ranges. Bring it up to the standard of the Emacs `*legu*` buffer without changing the `--json` contract that `emacs/legu.el` consumes.

Design agreed with the user:

1. Header: the three numbers for the scope (never read / read / stale), bars on one shared scale, sliver and percent rules as in Emacs; bar width from the terminal when stdout is a tty, otherwise fixed.
2. Path column sized to the longest path, capped at 60, cut from the left with an ellipsis.
3. Unreviewed shown as its own column; no per-file percent.
4. Fully-read files stay listed, their ranges cell says `read in full`; `--gaps` hides them. No per-directory subtotals.
5. Color when stdout is a tty, honouring NO_COLOR.
6. Empty states named.
7. JSON gains one additive key `coverage` for the scope; `files[]` and `tickets[]` keep their shape.

## Notes

**2026-09-09T02:46:15.210891606Z**

legu status now opens with the three numbers for its scope as three bar rows, sizes the path column to content (capped at 60, cut from the left), shows an UNREAD column, says 'read in full' instead of dumping a whole-file range, hides fully-read files behind --gaps, colours only on a tty and honours NO_COLOR, and names its empty states. --json keeps files[] and tickets[] unchanged and gains a coverage object. README documents --gaps. 123 ERT tests pass.
