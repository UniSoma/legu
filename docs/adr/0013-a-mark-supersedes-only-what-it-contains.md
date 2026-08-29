# A mark supersedes only the review records it fully contains

A re-read of a stale region used to leave a ghost: the old record survived
unless the new mark landed on exactly the lines it now anchored to, and only
`forget` removed it. A mark now retires every review record whose current
anchor lies inside the marked range. Partial overlap retires nothing: a partly
re-read region is not a read region, so the old record stays, `stale` keeps
naming its whole range, and only the re-read lines count as reviewed. An
opaque region has no line range, so only a mark of the whole file retires its
record. Ticket references are independent anchors and are not touched by a
mark.

## Considered options

- Any overlap retires the old record: silently drops coverage of the lines
  the new mark did not reach.
- Retire on overlap and re-record the uncovered remainder: the synthesised
  record would carry the working-tree hash and report lines nobody read as
  reviewed.
