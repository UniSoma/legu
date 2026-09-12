# Content hashes normalize per-line whitespace and nothing more

Amended by [ADR-0019](0019-indentation-is-significant-relative-to-the-region.md):
the stored hash keeps this trim, but anchoring judges leading whitespace
relative to the region once the read text is confirmed at a commit.

Before hashing a region, each line is stripped of leading and trailing
whitespace. That is the whole normalization. Anything more aggressive —
ignoring comments, collapsing tokens, reformatting — would need to know what a
comment or a token is, which is language knowledge (ADR-0001). The consequence
is that a reformat that changes more than indentation makes a region stale even
though nothing semantic changed; that is accepted as the honest answer.
