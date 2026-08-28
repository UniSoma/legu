# Content hashes normalize per-line whitespace and nothing more

Before hashing a region, each line is stripped of leading and trailing
whitespace. That is the whole normalization. Anything more aggressive —
ignoring comments, collapsing tokens, reformatting — would need to know what a
comment or a token is, which is language knowledge (ADR-0001). The consequence
is that a reformat that changes more than indentation makes a region stale even
though nothing semantic changed; that is accepted as the honest answer.
