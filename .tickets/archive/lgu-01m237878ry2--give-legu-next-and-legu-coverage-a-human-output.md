---
id: lgu-01m237878ry2
title: Give legu next and legu coverage a human output worth reading
status: closed
type: task
priority: 2
mode: afk
created: '2026-09-09T13:55:51.704835903Z'
updated: '2026-09-09T14:28:15.334420632Z'
closed: '2026-09-09T14:28:15.334420632Z'
acceptance:
- title: coverage prints the three numbers as bar rows, and names an empty store
  done: true
- title: next opens with a heading naming the count shown, the total with gaps, and the order
  done: true
- title: next rows size the path column to content and show UNREAD and STALE as columns
  done: true
- title: next --json and coverage --json are byte-identical to before
  done: true
- title: the human renderer of both still answers over a corrupt sidecar
  done: true
- title: README describes what next and coverage now print
  done: true
---

## Description

`legu status` now opens with the three numbers as bar rows and prints a table sized to its content. `legu next` and `legu coverage` still print the flat fixed-width output that predates it: `next` pads every path to 52 columns and repeats the words `unread` and `stale` on each row, `coverage` prints five `%7d` lines with no bars and no empty state.

Bring both up to the same standard, without touching either `--json` payload — `emacs/legu.el` and the ERT integration tests read them key for key.

1. `coverage` prints the same three-row block `status` opens with (never read / read / stale on one bar scale, then the eligible line), and names the empty store instead of drawing three empty bars.
2. `next` opens with a queue heading — how many files it is showing, of how many with gaps — and names its order: directory order, or co-change with what has been reviewed.
3. `next` rows use the `status` table idiom: path column sized to content, capped at 60 and cut from the left; UNREAD and STALE as their own columns, dimmed at zero; the ranges last, saying `whole file` where nothing has been read.
4. Colour only on a tty, honouring NO_COLOR, as `status` does.
5. No new options and no new JSON keys.

## Notes

**2026-09-09T13:59:30.282706984Z**

next now prints a QUEUE heading (files shown, files with gaps, order) and a table sized to its content — path capped at 60 and cut from the left, UNREAD and STALE as columns dimmed at zero, `whole file` where nothing has been read. coverage prints the same three bar rows status opens with, and names an empty store. render-files' path/count column arithmetic moved into shared path-column, num-column and cell helpers; num-column now sizes to the longest heading, which also straightens status's UNREAD header, previously one column off.

--json unchanged for both, key for key. ERT could not run here — no emacs on this machine — so the checks were: JSON key shapes before and after, a replication of the cochange ordering test (c/z.txt, b/y.txt, d/w.txt with unreviewed 8 and ranges 1-8), and the human renderer of both commands over a corrupt sidecar.
