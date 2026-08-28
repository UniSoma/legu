---
id: lgu-01m147n30cnf
title: A per-file regions query for editors
status: open
type: feature
priority: 2
mode: hitl
created: '2026-08-28T13:06:25.932820481Z'
updated: '2026-08-28T13:06:26.027354322Z'
acceptance:
- title: '`legu regions <path> --json` reports every region of one file with structured start/end, state, reason and provenance'
  done: false
- title: It is measurably faster than `status` on a 700-file repository; record both numbers on the ticket
  done: false
- title: Opaque (binary and empty) files, untracked files and ignored files each have a defined, documented answer
  done: false
- title: It has a human-readable renderer as well as --json
  done: false
- title: The Emacs package uses it and its range-string parser is deleted
  done: false
deps:
- lgu-01m147kahq96
---

## Description

An editor showing one open file has to ask the whole repository about itself.
`status --json` computes every eligible file before filtering by path, so
scoping it to one file costs the same as not scoping it; per-file *stale ranges*
are not in `status` at all, only in the repo-wide `stale`; and the reviewed
ranges come back as a formatted display string (`"40-95,120"`, with `"-"` for
empty) that every client has to re-parse.

One command answering for one file, cheap enough to run when a file is opened:

    $ legu regions src/core.clj --json
    {"path": "src/core.clj",
     "total": 169,
     "regions": [{"start": 40, "end": 95, "state": "reviewed",
                  "commit": "a1b2c3…", "reviewer": "jonas",
                  "timestamp": "2026-08-28T01:00:00Z",
                  "reason": null, "notes": ["lgu-01k7"]},
                 {"start": 112, "end": 130, "state": "stale",
                  "reason": "content changed", ...}]}

Structured start/end pairs, per-region state and reason, and the provenance a
client currently has to read out of the sidecar itself.

Open questions to settle before building: whether the repo-wide commands should
emit structured pairs too (and what that does to their human output), whether an
opaque region is expressed as a null range or its own state, and what this
reports for a file outside the eligible set.

The Emacs package would drop its range-string parser and its own EDN reader's
provenance duties in favour of this, and gets per-file stale ranges it currently
has to filter out of the repo-wide list.
