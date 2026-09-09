# Sidecars are written in a fixed layout, one self-contained record at a time

A sidecar used to be pretty-printed: width-dependent wrapping, a redundant
`:path`, and opaque records carrying `nil` bounds and a duplicate hash. A mark
could re-wrap lines it did not touch, so a diff of the store was not a diff of
the reviews. The sidecar is now `:schema 2` and written in a fixed layout: the
region on one line, reviewer or ticket with the timestamp on the next, then
the commit and each full hash on a line of its own, and every collection
delimiter on a line of its own. Records are sorted by region with the
remaining fields as tie-breakers, so identical state is identical bytes. The
path is derived from the sidecar's location; an opaque record keeps only the
opaque flag and the file hash. Adding or forgetting a record changes only its
own lines, separate edits merge, and competing edits to one record are a
conflict git shows. Review semantics are unchanged: supersede, forget, rename
following and the refusal to follow copies read the new layout exactly as they
read the old. There are no stores outside this repository, so older schemas
are refused rather than migrated, by the CLI and by Emacs alike.

## Considered options

- Group records under a shared `(commit, file-hash)`: 37% fewer raw bytes at
  20 records per file, but no better merge outcomes, worse with one version
  per record, and a record's evidence ends up outside the diff context of the
  lines that changed ([experiment](../experiments/review-store-encoding.md)).
- Shortened hashes or generated record ids: smaller, but a truncated hash is
  weaker evidence and an id is one more thing for two branches to collide on.
- Keep pretty-printing and rely on `git diff -w`: wrapping changes are not
  whitespace changes, and the source path and nil bounds would still be noise.
