---
id: lgu-01m26gbjmqjc
title: Retire read / unread from status, next and the Emacs views
status: open
type: chore
priority: 3
mode: afk
created: '2026-09-10T20:32:42.134969838Z'
updated: '2026-09-10T20:32:49.263368307Z'
parent: lgu-01m238vjgnh6
acceptance:
- title: status and next headers and cells use the glossary's words, or an ADR records why a table keeps a shorter one
  done: false
- title: The Emacs coverage block and echo lines match the CLI's coverage rows
  done: false
- title: The CLI suite and the ERT suite pin the wording that wins
  done: false
links:
- lgu-01m23d9faenk
---

## Description

lgu-01m23d9faenk moved `coverage` onto CONTEXT.md's words: its rows now read unreviewed / reviewed / stale and its JSON key is `unreviewed`. Other output still uses words the glossary lists under _Avoid_ — "read" for **Reviewed**, "unread" and "never read" for **Unreviewed**:

- the `status` and `next` table headers `READ`, `UNREAD` and `READ RANGES`, and the "read in full" cells (legu, render-files and render-queue)
- README's `next` section, which calls the counts "unread", matching those headers
- the Emacs coverage block and echo lines: legu-list.el ("never read" row), legu.el (the coverage message), legu-transient.el ("% read · % stale · % never read")

The same `coverage` block that `status` opens with now says unreviewed / reviewed, so the Emacs list's coverage block, which mirrors it, now disagrees with the CLI. No JSON key is involved: status and next already emit `unreviewed`.
