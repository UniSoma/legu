---
id: lgu-01m25t7y4zzf
title: Write sidecars as JSON Lines, one record per line
status: closed
type: task
priority: 1
mode: afk
created: '2026-09-10T14:06:14.175013111Z'
updated: '2026-09-10T14:37:27.811430225Z'
closed: '2026-09-10T14:37:27.811430225Z'
acceptance:
- title: 'A sidecar is schema 3 at .review/<path>.jsonl: header line, review records sorted by region, then ticket references sorted by region, one record per line in the key order of ADR-0015, no whitespace, whole-second timestamps, and identical state is identical bytes'
  done: true
- title: The CLI reads a sidecar per line with cheshire and refuses the whole sidecar when any line fails to parse or the header is not schema 3; the ERT test that a write to a broken sidecar is refused, and the CLI suite, pass
  done: true
- title: legu.el reads sidecars with json-parse-string, legu-sidecar-schema is 3, and the legu--edn-* reader and its five tests are deleted
  done: true
- title: A committed .gitattributes marks .review/** linguist-generated=true and gitlab-generated=true
  done: true
- title: The fixture generators of the encoding and latency experiments emit schema 3, and coverage, status and stale --json hash identically on the regenerated clean and stale fixtures at 10,000 files and 20 records
  done: true
- title: mark at 10,000 files and 20 records is timed in three fresh-process trials before and after, on one core, and recorded on this ticket and as a note on lgu-01m249cd9v2h
  done: true
- title: README.md, emacs/README.md and the --version output say schema 3 and .jsonl wherever they said EDN, and the ERT count in emacs/README.md matches the suite
  done: true
links:
- lgu-01m249cd9v2h
- lgu-01m249cd6dgq
- lgu-01m249cddd06
- lgu-01m25t8643d6
external_refs:
- git:ab6cbaa8ca8a6d78610526abf302f76eea215535
---

## Description

ADR-0015 moves the store from the fixed-layout EDN of ADR-0014 to JSON Lines
so that a mark, a supersede or a forget shows in a pull request as one changed
line instead of four to six. The ADR fixes the format; this ticket lands it.

The file: `{"schema":3}` on the first line, then every review record on one
line sorted by region with the remaining fields as tie-breakers, then every
ticket reference sorted the same way. A line is rendered by hand in the order
of `record-lines`, hyphenated keys, no whitespace after separators: region,
reviewer or ticket with the timestamp, commit, file hash, content hash. An
opaque record keeps only the opaque flag and the file hash. Timestamps are
whole seconds. An empty sidecar is still deleted. A record is a review record
when it has a `reviewer` and a ticket reference when it has a `ticket`.

Reading: `parse-sidecar-file` splits on newlines and parses each with
`cheshire.core/parse-string` with keyword keys. A failed line, a missing
header or a schema other than 3 makes the whole sidecar unreadable, so the
merge-conflict refusal of ADR-0010 is unchanged. `legu--read-edn` and the
`legu--edn-*` functions give way to `json-parse-string` with the same never-
signals contract: anything that is not a well-formed sidecar reads as nil.

There is no migration: no store exists outside this repository, and schema 2
is refused as ADR-0014 already says. The encoding experiment's fixtures and
the latency experiment's fixtures are EDN today; regenerate them, since every
later measurement on the parse tickets is taken on this format. A scratch
benchmark on the same 10,000 by 20 shape measured 0.75 s for JSONL against
2.37 s for EDN, warm, in one bb process; record the real number on
lgu-01m249cd9v2h, which is waiting on it.

Out of scope: a textconv diff driver, coalescing adjacent records, and any
cache outside the store.

## Notes

**2026-09-10T14:29:07.661510085Z**

Measured on 2026-09-10 with the latency experiment's recipe: 10,000 source
files of 220 lines, 20 records each, fixtures built by bench.py before and
after this change (EDN schema 2 by the generator at 728137f, JSONL schema 3
by the one at 7762cd6). Before is the CLI at f52aea8 on the EDN fixture;
after is this change on the JSONL fixture. Babashka 1.13.220, Git 2.47.3,
i9-13900HX, warm page cache.

Equivalence: `coverage --json`, `status --json` and `stale --json` hash
identically before and after, on the clean fixture and on the stale one
(the first twenty lines of every fifth file edited): six of six pairs equal.

mark of src/d0000/f00000.txt:201-210, one core (`taskset -c 0`), three
fresh processes each, in seconds:

| | trial 1 | trial 2 | trial 3 |
| --- | ---: | ---: | ---: |
| before, EDN schema 2 | 2.560 | 2.586 | 2.567 |
| after, JSONL schema 3 | 1.911 | 1.922 | 1.918 |

0.65 s off a 2.57 s mark, 1.34x. The scratch benchmark's 3.2x was the parse
alone in a warm process; a fresh `mark` also lists the store, stats every
sidecar, asks git four times and starts the JVM, none of which the format
touches. Read commands on the clean fixture came down 0.5 to 0.8 s as well
(coverage 3.64 s to 3.11 s), not timed under the three-trial protocol.

One merge outcome changed: two branches re-reading neighbouring records now
conflict, since the two edited lines are adjacent with no unchanged line
between them; under ADR-0014 the hash lines of the first record kept them
apart. Recorded in ADR-0015 and pinned by the ERT test
legu-test-integration-adjacent-edits-to-one-sidecar-conflict. Edits to
records one line apart still merge.

The prototype branches carry the generator changes: 7762cd6 on
prototype/mark-coverage-latency and 8239563 on
prototype/review-store-encoding.

**2026-09-10T14:36:29.917334945Z**

Corrected timing. The table in the note above was taken with a reader that
called cheshire's parse-string per line; the code review found that
parse-string stops at the end of the first value and would pass a line with
anything after it, so the reader now reads each line as a value sequence and
refuses a line holding other than one. Re-timed with that reader, same
protocol (10,000 files, 20 records, clean, one core, three fresh processes,
warm page cache), in seconds:

| | trial 1 | trial 2 | trial 3 |
| --- | ---: | ---: | ---: |
| before, EDN schema 2 | 2.622 | 2.593 | 2.556 |
| after, JSONL schema 3 | 1.170 | 1.179 | 1.206 |

2.2x, 1.4 s off a 2.6 s mark. The six equivalence hashes are unchanged and
still identical. Clean coverage came down from 3.9 s to 2.4 s in the same
run, one trial each.

**2026-09-10T14:37:27.811430225Z**

Sidecars are schema 3 JSON Lines at .review/<path>.jsonl, read per line by cheshire in the CLI and json-parse-string in legu.el, with the EDN reader deleted, .gitattributes marking the store generated, both fixture generators on schema 3, identical coverage/status/stale hashes across the change, and mark at 10,000x20 down from 2.6 s to 1.2 s on one core. One merge outcome changed: neighbouring records re-read on two branches now conflict, recorded in ADR-0015.
