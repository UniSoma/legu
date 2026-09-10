---
id: lgu-01m26j64rmqk
title: Retire read as a state name from Emacs prompts and help-echo
status: closed
type: chore
priority: 3
mode: afk
created: '2026-09-10T21:04:41.236901325Z'
updated: '2026-09-10T21:41:53.304272234Z'
closed: '2026-09-10T21:12:22.430980132Z'
acceptance:
- title: Prompts, help-echo and cells that name the Reviewed state say reviewed
  done: true
- title: ERT pins the help-echo wording
  done: true
links:
- lgu-01m26gbjmqjc
external_refs:
- git:33fbcf39e82341f99cd7537fdb4f485203b2cc83
---

## Description

lgu-01m26gbjmqjc moved the tables, the coverage block and the echo lines onto CONTEXT.md's words. Other Emacs strings still use "read" as the name of the **Reviewed** state, which the glossary lists under _Avoid_:

- legu-overlay.el help-echo: "legu: read", "legu: read, but the content has changed"
- legu.el mark prompts and docstrings: "Mark %d lines (%d-%d) read?", "Mark this whole file read."
- legu-list.el: "Record %d file%s read in full, unopened", "Re-mark %d stale regions read?", the stale row's "read <date>" cell

Where "read" describes what the reader does ("what to read next", "re-read"), it stays.

## Notes

**2026-09-10T21:05:49.315700409Z**

Two more spots: legu-transient.el's menu group titled "Read", and emacs/README.md's lighter description, which calls the percentage the lines "read".

**2026-09-10T21:12:22.430980132Z**

Prompts, docstrings, help-echo and cells that named the Reviewed state 'read' or the Unreviewed state 'unread' now say reviewed / unreviewed: the overlay help-echo, the mark prompts in legu.el and legu-list.el (the unopened-file prompt now says 'fully reviewed', as status does), the stale row's date cell, the diff header's date cell, the menu group (now 'Mark'), the gap and queue docstrings, and the Emacs README's lighter and tier-rule wording. Beyond the ticket's list: legu-diff.el's header, the 'unread or stale' docstrings, and README's 'read, in place'. A new ERT case pins the reviewed and stale help-echo; the suite runs 157 tests, 0 unexpected, 6 evil skips.
