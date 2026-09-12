# Only the lines a change touched are stale, derived at anchoring time

ADR-0004 made any change inside a reviewed region stale the whole region, and
said to revisit if that proved noisy on a real repository. It did, through
ADR-0013: after a one-hunk edit to a 150-line record, re-reading and marking
the hunk left the old record partly outside the new mark, so it survived,
`stale` kept naming all 150 lines, and only a full re-read or a `forget`
cleared it. Anchoring now returns fragments of a record: the lines each hunk
touched are stale, the lines between hunks are reviewed at their shifted
location, and a pure deletion leaves one stale line at the seam. Nothing in
the store changes. The record stays one signed line for its whole range,
because legu never observes the edit (ADR-0006) and splitting a record would
need a new signature from whoever ran the command (ADR-0016). The reviewed
fragments carry no hash of their own; they are trusted on the diff, which is
exact because it is taken from the file at the reviewed commit, and only
after the record's content hash is confirmed against that commit. A mark
made on a dirty working tree cites a commit whose text it did not read, so
when the recorded commit does not confirm the hash the later commits that
touched the path are tried in order, a few at most, and the first that
confirms is diffed against instead. A record no commit confirms, or a file
with no git to diff against, falls back to whole-region stale. The blobs
are read through one batched `git cat-file`, as the hunks already come from
one `git diff` per commit. A mark that covers a record's stale fragments
does not retire the record: it is the only evidence for the fragments still
reviewed, and a line covered by a newer read is reviewed by the existing
line-level rule. Region size no longer affects staleness; it still bounds
what one record vouches for, so the guidance to mark what you can hold in
your head stands. Supersedes ADR-0004.

## Rules at the edges

- A hunk whose old and new lines hash the same under ADR-0003's per-line
  trim is not a change: its lines are reviewed, as a whole-file reindent
  already is. The trim's blind spot for indentation-carrying languages is
  ADR-0003's and is unchanged here.
- A hunk that straddles the region boundary has no line-to-line mapping
  inside it. Its stale fragment is clipped by prefix: it starts at the hunk's
  new start plus the region's offset into the hunk's old lines, and a hunk
  that shrank below that offset leaves a seam line. The record never claims
  a line it did not cover.
- The seam of a deletion is the line after it when that line is still inside
  the region, else the line before it. A record whose every line was deleted
  has no seam and is stale at the clamped range the code already reports.
- The moved-block search stays ahead of fragmenting and looks for the whole
  region only. A part of a region cut and pasted elsewhere leaves a seam
  where it was and counts unreviewed where it landed; only the whole read is
  evidence.

## Considered options

- Stale hunk plus N lines of context, on the ADR-0004 argument that a small
  change can invalidate its surroundings: a guess about comprehension the
  tool cannot make, and a stale count that depends on a magic number.
- Split the record on disk into reviewed and stale pieces: the synthesised
  record ADR-0013 rejected, now also unsignable by its original reviewer.
- Retire a record once a mark covers its stale fragments: drops the signed
  evidence for the lines that were never re-read.
- Whole hunk stale when it straddles the boundary: simpler, but turns
  neighbouring lines nobody read into stale, which outranks unreviewed.
