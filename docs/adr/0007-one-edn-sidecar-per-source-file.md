# Review state lives in one committed EDN sidecar per source file

Superseded by [ADR-0015](0015-jsonl-sidecars-one-record-per-line.md): the
store is JSON Lines. The one-sidecar-per-file shape and the reasons for it
stand.

The store is `.review/` at the repo root, mirroring the source tree, one
`<path>.edn` per source file, committed alongside the code. Source files are
never modified. A single index file would be simpler but two reviewers would
conflict on every mark; `git notes` would attach state to objects without
touching the tree but has a sync story nobody understands. EDN because the
format must be human-readable and diffable, and legu is written in babashka.

## Considered options

- One index file at the root: constant merge conflicts with more than one
  reviewer.
- `git notes`: no files in the tree, but awkward to push, fetch and merge.
- JSON: equally readable; EDN was picked for the implementation language, and
  nothing else consumes the store directly.
