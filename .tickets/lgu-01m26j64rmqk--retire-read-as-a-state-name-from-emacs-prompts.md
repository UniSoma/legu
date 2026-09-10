---
id: lgu-01m26j64rmqk
title: Retire read as a state name from Emacs prompts and help-echo
status: open
type: chore
priority: 3
mode: afk
created: '2026-09-10T21:04:41.236901325Z'
updated: '2026-09-10T21:04:46.177798798Z'
acceptance:
- title: Prompts, help-echo and cells that name the Reviewed state say reviewed
  done: false
- title: ERT pins the help-echo wording
  done: false
links:
- lgu-01m26gbjmqjc
---

## Description

lgu-01m26gbjmqjc moved the tables, the coverage block and the echo lines onto CONTEXT.md's words. Other Emacs strings still use "read" as the name of the **Reviewed** state, which the glossary lists under _Avoid_:

- legu-overlay.el help-echo: "legu: read", "legu: read, but the content has changed"
- legu.el mark prompts and docstrings: "Mark %d lines (%d-%d) read?", "Mark this whole file read."
- legu-list.el: "Record %d file%s read in full, unopened", "Re-mark %d stale regions read?", the stale row's "read <date>" cell

Where "read" describes what the reader does ("what to read next", "re-read"), it stays.
