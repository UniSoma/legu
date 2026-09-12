---
id: lgu-01m29h4g9n4s
title: 'Per-hunk staleness: only the lines a change touched go stale'
status: closed
type: feature
priority: 1
mode: afk
created: '2026-09-12T00:44:02.229444143Z'
updated: '2026-09-12T04:47:28.556451620Z'
closed: '2026-09-12T04:47:28.556451620Z'
tags:
- ready-for-agent
---

## Problem Statement

A reader marks a 150-line file as one region. Later a 25-line edit lands
inside it. Today the whole region goes stale: the coverage numbers say 150
lines were lost, `legu next` sends the reader back to line 1, and after the
reader re-reads only the changed lines and marks them, the old record
survives partly outside the new mark, so `legu stale` keeps naming all 150
lines until the whole file is re-read or forgotten. Whole-region staleness
(ADR-0004) said to revisit when it proved noisy on a real repository, and
through the supersede rule of ADR-0013 it has.

A second, older gap: content hashes trim every line, so a statement dedented
out of a Python `if`, a YAML key moved up a level or a Makefile recipe line
unindented anchors as reviewed with its meaning changed.

## Solution

Anchoring splits a review record into fragments. The lines a hunk touched
are stale, the lines between hunks stay reviewed at their shifted location,
and a pure deletion leaves one stale line at the seam. Nothing in the store
changes: the record stays one signed line, and only what anchoring reports
about it changes. `legu stale` lists one item per stale fragment and drops
fragments a newer reviewed record covers, `legu next` jumps to the first
stale line, and coverage counts only the touched lines as stale.

Whitespace is judged between the text that was read and the text on disk at
anchoring time, once the record is confirmed against a commit: trailing
whitespace never matters, leading whitespace matters relative to the region.
Wrapping a block in a new `def` stays reviewed; moving one line to another
level goes stale.

Decisions are recorded in ADR-0018 (supersedes ADR-0004) and ADR-0019
(amends ADR-0003). The Stale term in CONTEXT.md is already updated.

## User Stories

1. As a reader, I want a small edit inside a large reviewed region to mark only the edited lines stale, so that the stale count tells me how much I have to re-read.
2. As a reader, I want `legu next` to take me to the first changed line rather than the start of the region, so that I re-read only what changed.
3. As a reader, I want to re-read and mark just the changed lines and see nothing stale afterwards, so that a partial re-read is a complete answer to a partial change.
4. As a reader, I want the lines below an insertion to stay reviewed at their new position, so that adding code above what I read does not cost me the read.
5. As a reader, I want a pure deletion inside a region to leave exactly one stale line at the seam, so that a deletion is never invisible and never costs more than one line.
6. As a reader, I want a deletion at the end of a region to put its seam on the last remaining line of the region, so that the seam is always inside what I read.
7. As a reader, I want a record whose every line was deleted to report stale at the clamped range it reports today, so that nothing silently disappears.
8. As a reader, I want several hunks inside one region to produce one stale item each, so that `legu stale` is a list of places to go.
9. As a reader, I want a reindent that moves a whole block together to stay reviewed, so that wrapping code in a new block asks me to read the new line, not the block.
10. As a reader, I want a reindent next to a real edit to stay reviewed for the reindented lines, so that the same whitespace edit is judged the same whether or not it is alone.
11. As a reader of Python, YAML or Makefiles, I want a line that changed its indentation relative to the rest of the region to go stale, so that a change of meaning is never hidden by whitespace normalization.
12. As a reader, I want trailing-whitespace edits, CRLF flips and a trailing-newline change never to count as changes, so that editor churn does not cost me a read.
13. As a reader, I want tab-to-space conversion to count as a reformat and go stale, so that relative indentation stays trustworthy.
14. As a reader, I want a hunk that straddles the boundary of my region to mark stale only the lines the region covered, so that stale never claims a line nobody read.
15. As a reader, I want a whole region cut and pasted elsewhere in the file to still count as moved, not stale, so that fragmenting takes nothing away from today's anchoring.
16. As a reader, I want a part of a region cut and pasted elsewhere to leave a seam where it was and count unreviewed where it landed, so that only a whole read is treated as evidence.
17. As a reader who marks while working on uncommitted code, I want fragmenting to work even though the record cites a commit whose text I did not read, so that the reading loop gets the benefit too.
18. As a reader, I want a record no commit can confirm, and a store with no git, to behave exactly as today, so that fragmenting never makes a result worse than whole-region staleness.
19. As a reviewer of the store, I want no record ever rewritten or re-signed by this feature, so that every existing signature keeps holding and no read is misattributed.
20. As a reviewer of the store, I want the old record kept after I mark only its stale fragment, so that the signed evidence for the lines I did not re-read is never dropped.
21. As a reviewer of the store, I want the sidecar schema to stay at 4, so that no migration is needed.
22. As an Emacs user, I want the gutter to paint the reviewed and stale fragments of one record, so that the editor and `legu status` agree line by line.
23. As an Emacs user, I want `legu regions --json` to keep the same item shape, one item per fragment each carrying the original record's provenance, so that the editor needs no protocol change.
24. As a user of `legu stale --json`, I want the same keys per item as today, so that scripts keep working.
25. As a user of `legu regions`, I want each fragment to say whether it is moved from its own offset, so that a shifted lower fragment is reported moved while the upper one is not.
26. As a user on a large repository, I want the blobs needed for confirmation read through one batched git process per run, so that `legu status` does not spawn one process per changed file.
27. As a user on a large repository, I want no new work on files that are byte-identical or merely shifted, so that the common case stays as fast as today.
28. As a reader of the README, I want the staleness section to describe fragments and the relative-indentation rule, and the guidance to say what region size now bounds, so that the docs do not give a reason that is no longer true.
29. As a reader of the README, I want the known limit about `stale` naming a partly re-marked record's whole range removed, so that the docs match the tool.

## Implementation Decisions

- The store, the sidecar schema (4), the record shape and the signatures do not change. Fragmenting is derived at anchoring time only.
- Anchoring's ladder keeps its order: byte-identical file is reviewed; then projection across hunks and the region hash; then the moved-block search for the whole region; and only where today returns whole-region stale does the fragment step run. No new work on the reviewed or moved paths.
- Confirmation: before trusting hunks, the record's content hash (ADR-0003 trim) must match the region as it was in the file at the recorded commit. If it does not, the later commits that touched the path are tried in order, capped at a small number, and the first that confirms is the commit diffed against. A record no commit confirms, or a store with no git, falls back to whole-region stale.
- Blob reads for confirmation go through one batched `git cat-file --batch` process per run, cached per commit and path, mirroring how hunks are fetched with one `git diff` per commit. The old text of a changed file is held for the run, the same order of memory as the hunk cache.
- Fragment rules, per hunk inside the projected region:
  - A hunk whose old and new lines are equal after trailing-whitespace trim is not a change; its lines are reviewed.
  - Otherwise the hunk's new-side lines are stale.
  - A pure deletion has no new lines; its seam is the line after it if that line is inside the region, else the line before it. A record whose every line was deleted has no seam and reports stale at the clamped range the code already produces.
  - A hunk straddling the region boundary is clipped by prefix: the stale fragment starts at the hunk's new start plus the region's offset into the hunk's old lines, and a hunk that shrank below that offset leaves a seam line. The record never claims a line it did not cover.
  - Lines between hunks are reviewed at their shifted position; a fragment is moved when its own offset is nonzero.
- Region-relative indentation (ADR-0019): after the strict per-hunk pass, one check compares the old text with only the strict hunks applied against the new text under region-relative normalization: remove the leading whitespace common to every line of each text, then trim the end of each line. If they differ, the whitespace-equal hunks that broke the offsets are stale too. The stored hash keeps ADR-0003's trim so every existing record still confirms.
- The moved-block search looks for the whole region only. A partial move leaves a seam and counts unreviewed where it landed.
- Consumers: the per-path resolution yields one range per fragment instead of one per record; the line-level rule that a line covered by any reviewed fragment is reviewed is unchanged and now receives finer input. `legu stale` prints one item per stale fragment, sorted by path and start, and drops fragments a reviewed fragment covers. `legu regions` returns one item per fragment, each carrying the original record's provenance, so the Emacs side needs no protocol change. `legu next` and the gap follow from the line-level state.
- The supersede rule of ADR-0013 is unchanged: a mark retires only records it fully contains. A record whose stale fragment is covered by a newer mark survives as the evidence for its reviewed fragments.
- README: the staleness section describes fragments, the relative-indentation rule and the seam; the guidance paragraph says region size bounds what one record vouches for; the known limit about a partly re-marked record's whole range is removed.
- Opaque regions are hash-only and untouched by this feature.

## Testing Decisions

- The seam is the CLI: run `legu` against a scratch git repository and assert on the JSON of `stale`, `status`, `coverage`, `next` and `regions`, and on the text output where it is the contract. No new seam is introduced; fragmenting is observable entirely through the commands.
- A good test names a file modification and asserts the reported ranges and states, never how the ladder got there. Cover, each as its own case:
  - edit in place; edit that grows; edit that shrinks; insertion inside; pure deletion inside; deletion at the region's end; deletion of the whole region; several hunks; edits only above the region (moved, no fragments); insertion right before and right after the region;
  - re-read and mark of the stale fragment: `stale` reports nothing, coverage counts every line reviewed, the sidecar holds both records;
  - whole-region cut and paste (moved); partial cut and paste (seam plus unreviewed);
  - hunk straddling the region start and the region end, with a neighbouring unreviewed range that must stay unreviewed;
  - reindent of a whole block; reindent next to a real edit; one line dedented out of a block; trailing whitespace, CRLF flip and trailing-newline change; tab-to-space conversion;
  - mark on a dirty working tree then commit then edit (fragments via the forward search); record citing an unreachable commit (whole-region fallback); no git (whole-region fallback);
  - `regions --json` one item per fragment with the original provenance, `moved` per fragment.
- Prior art: the CLI suite in the test directory already builds scratch repositories, marks, edits, commits and asserts on JSON output for anchoring, renames, moves and the supersede rule; the new cases follow that shape. The Emacs ERT integration tests that call `legu regions --json` are the regression check for the editor.
- A process-count assertion is not required, but the batched reader should be exercised by a test with several changed files across two commits.

## Out of Scope

- Any change to the store, the sidecar schema, the record shape, signing or `verify`.
- Changing the stored hash's normalization or migrating existing records.
- Following a partially moved block to its new location.
- Context padding around a hunk.
- Fragmenting opaque regions.
- Language-aware normalization of any kind.
- Editor changes beyond what the unchanged JSON shape already supports.

## Further Notes

- Design walkthrough with diagrams for every scenario: https://claude.ai/code/artifact/b66b54a3-ad71-4f50-9be4-640cd80654a6
- ADR-0018 holds the five edge rules and the rejected options; ADR-0019 the indentation rule. CONTEXT.md already defines Stale per line.
- The dirty-working-tree case is the one most likely to be hit in practice by anyone marking from the editor mid-edit; without the forward search the feature would be silently absent for them.

## Notes

**2026-09-12T04:47:28.556451620Z**

Staleness is per hunk (ADR-0018) and indentation is significant relative to the region (ADR-0019). Anchoring splits a confirmed review record into fragments: the lines each hunk wrote are stale, the runs between them stay reviewed where the hunks left them, and a change that leaves the region no line of its own is stale at one seam. A hunk crossing the region's boundary is clipped by prefix, so a record never claims a line it did not cover. Whitespace is judged between the text that was read and the text on disk, so a block reindented together stays reviewed while a line moved to another level goes stale. A mark taken on a dirty working tree is confirmed against the first later commit that holds what was read. Nothing in the store changed: schema 4, the record keys and the signatures are untouched, and mark and forget still read whole records. Landed in 1e1d454, 319724f and baf21fe. Four follow-ups are filed: lgu-01m29qss37ee, lgu-01m29sm9600c, lgu-01m29ywrrzjj, lgu-01m29yx66fx9.
