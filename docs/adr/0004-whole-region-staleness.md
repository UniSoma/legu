# Any change inside a region makes the whole region stale

Superseded by [ADR-0018](0018-staleness-is-per-hunk-not-per-region.md):
only the lines a hunk touched are stale.

There is no partial invalidation: a one-line edit inside a reviewed region
marks all of it stale. A small change can invalidate understanding of the
whole, and per-line state would need per-line records and a far more complex
anchoring story. The cost — large regions go stale often — is met with
guidance rather than code: mark regions roughly the size you can hold in your
head at once. Revisit only if whole-region invalidation proves too noisy on a
real repository.
