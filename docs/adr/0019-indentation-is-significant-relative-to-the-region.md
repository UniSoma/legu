# Indentation is significant, relative to the region

ADR-0003 trims each line before hashing, so a statement dedented out of an
`if` in Python, a key moved up a level in YAML or a recipe line unindented
in a Makefile all anchor as reviewed with their meaning changed. ADR-0018
makes this fixable at no cost to the store: anchoring now confirms a record
against the file at a commit before trusting the diff, so from that point
it holds the exact text that was read, and the stored hash is only the
pointer that found it. Whitespace equivalence is therefore judged between
old text and new text at anchoring time, not by the stored hash, and the
rule becomes: trailing whitespace never matters, and leading whitespace
matters relative to the region. Two texts are the same read when, after
removing the leading whitespace common to every line of each, they trim
equal at the end of each line. Wrapping a block in a new `def` or `if`, or
pulling it out of one, shifts every line together and the block stays
reviewed, while the inserted or removed line is stale under ADR-0018 as any
other; moving one line to another level changes its offset from the rest
and is stale, with no other character touched. A
per-hunk equivalence test cannot see this, since a dedented block is a hunk
whose lines are equal in isolation, so the fragment step judges hunks strictly
on trailing whitespace, then checks once that the old text with only the
strict hunks applied is region-equivalent to the new text; if it is not, the
whitespace hunks that broke the offsets are stale too. The stored hash keeps
ADR-0003's trim so that every existing record still confirms, and a record
that no commit confirms falls back to that trim alone, as it does today.
Tabs converted to spaces change relative offsets and go stale; that is a
reformat, and ADR-0003 already calls reformats stale. Amends ADR-0003.

## Considered options

- Trailing whitespace only, absolute indentation significant: makes every
  reindent stale, including wrapping a block, which is the reformat people
  do most and one no reader needs to repeat.
- Indentation significant only for files whose language cares: needs a
  language table, which ADR-0001 rules out.
- Change the stored hash to a new normalization and bump the schema: every
  record would need re-hashing from its commit and re-signing by whoever ran
  the migration, misattributing the read.
