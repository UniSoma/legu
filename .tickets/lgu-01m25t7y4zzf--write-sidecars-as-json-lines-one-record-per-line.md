---
id: lgu-01m25t7y4zzf
title: Write sidecars as JSON Lines, one record per line
status: open
type: task
priority: 1
mode: afk
created: '2026-09-10T14:06:14.175013111Z'
updated: '2026-09-10T14:06:32.887993809Z'
acceptance:
- title: 'A sidecar is schema 3 at .review/<path>.jsonl: header line, review records sorted by region, then ticket references sorted by region, one record per line in the key order of ADR-0015, no whitespace, whole-second timestamps, and identical state is identical bytes'
  done: false
- title: The CLI reads a sidecar per line with cheshire and refuses the whole sidecar when any line fails to parse or the header is not schema 3; the ERT test that a write to a broken sidecar is refused, and the CLI suite, pass
  done: false
- title: legu.el reads sidecars with json-parse-string, legu-sidecar-schema is 3, and the legu--edn-* reader and its five tests are deleted
  done: false
- title: A committed .gitattributes marks .review/** linguist-generated=true and gitlab-generated=true
  done: false
- title: The fixture generators of the encoding and latency experiments emit schema 3, and coverage, status and stale --json hash identically on the regenerated clean and stale fixtures at 10,000 files and 20 records
  done: false
- title: mark at 10,000 files and 20 records is timed in three fresh-process trials before and after, on one core, and recorded on this ticket and as a note on lgu-01m249cd9v2h
  done: false
- title: README.md, emacs/README.md and the --version output say schema 3 and .jsonl wherever they said EDN, and the ERT count in emacs/README.md matches the suite
  done: false
links:
- lgu-01m249cd9v2h
- lgu-01m249cd6dgq
- lgu-01m249cddd06
- lgu-01m25t8643d6
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
