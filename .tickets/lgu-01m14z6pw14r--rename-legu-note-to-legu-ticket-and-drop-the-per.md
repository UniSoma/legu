---
id: lgu-01m14z6pw14r
title: Rename legu note to legu ticket, and drop the per-record notes field
status: open
type: task
priority: 2
mode: afk
created: '2026-08-28T19:58:00.576729352Z'
updated: '2026-08-28T19:58:00.576729352Z'
acceptance:
- title: '`legu ticket <path>[:<range>] <id>` replaces `legu note`; `note` is gone from the command table and the usage text'
  done: false
- title: The sidecar vector is `:tickets`; `:schema` stays 1 (no users yet), and a sidecar with the old `:notes` key is read as an error, not silently ignored
  done: false
- title: The `:notes` field on review records is removed, along with the carry-over in `purge!`; a mark that supersedes a record leaves ticket references at that region in place
  done: false
- title: 'Emacs: `legu-note` and `legu-list-note` become `legu-ticket` and `legu-list-ticket`; keys, transient labels, faces and the fringe glyph name follow'
  done: false
- title: Both READMEs and CONTEXT.md use *ticket reference* throughout; the word note appears nowhere in user-facing text
  done: false
- title: The ERT suite and the CLI still pass; a test asserts a ticket reference survives a supersede of the region it sits in
  done: false
links:
- lgu-01m147mc4c8x
---

## Description

Decided in ADR-0012 (docs/adr/0012-rename-note-to-ticket.md): the command name lied about what it stores. `legu note` takes a ticket id, never prose, and the per-record `:notes` field was never written by anything — only carried from one superseded record to the next. Rename the command, the sidecar key and the Emacs commands; remove the dead field. No schema bump: there are no stores outside this repository yet.

The glossary term is **Ticket reference** (CONTEXT.md). Do not add a free-text comment alongside it; ADR-0008 and ADR-0012 record why.
