---
id: lgu-01m23d9faenk
title: Say what mark and coverage actually do, in the project's own words
status: open
type: chore
priority: 3
mode: afk
created: '2026-09-09T15:41:24.174873952Z'
updated: '2026-09-09T16:26:11.725312762Z'
acceptance:
- title: mark's help no longer says the region was reviewed at HEAD, and says what ADR-0006 and CONTEXT.md say instead
  done: false
- title: coverage's help, its human row label and its JSON key agree with each other and with CONTEXT.md, or an ADR records why the output keeps a word the vocabulary avoids
  done: false
- title: If the JSON key changes, emacs/legu.el is updated with it and the store schema or version implication is stated
  done: false
- title: The CLI suite pins whichever wording wins
  done: false
---

## Description

Two strings of user-facing help disagree with CONTEXT.md and an ADR. Both were carried verbatim from the usage blob into the dispatch tree's :doc lines during lgu-01m238wawfq7, which promised no behavior change, so rewording them was out of scope there.

`mark` reads `mark a region reviewed at HEAD`. ADR-0006 says review state is measured against the working tree, not HEAD, and CONTEXT.md defines **Mark** as declaring a region reviewed "as it stands in the working tree right now". HEAD is what the record cites as provenance, not what was read. The help says the opposite of the decision.

`coverage` reads `never-read / reviewed / stale`. CONTEXT.md lists `unread` under **Unreviewed**'s _Avoid_. This one is not a simple rename: `never read` is also the row label in coverage's own human output (legu:1021) and `:never-read` is a key in its JSON (legu:1219), so the help matches the tool and the tool disagrees with the vocabulary. Decide which moves — and if the JSON key moves, it is a breaking change for the Emacs package, which reads it.

## Notes

**2026-09-09T16:26:11.725312762Z**

Found while moving the CLI onto babashka.cli (lgu-01m238vjgnh6), which carried both strings verbatim from the old usage blob into the dispatch tree's :doc lines. Parented off that epic on close: the wording predates the move and outlives it, and the coverage half may imply a breaking JSON-key change for the Emacs package, which is not that epic's decision to make.
