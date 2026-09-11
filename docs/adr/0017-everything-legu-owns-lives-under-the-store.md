# Everything legu owns lives under `.review/`

Until now `.review/` held sidecars only and mirrored the source tree exactly,
while the ignore list sat at the repo root as `.reviewignore`. The signers
list of ADR-0016 is a second file that is neither a sidecar nor state, and a
flat `.review/signers` would collide with a source directory named `signers/`
and be hidden by the `.gitattributes` rule that collapses the whole store in
review views, when it is the one file that must be read in review. The store
is now the single directory for everything legu owns: sidecars under
`.review/sidecars/<path>.jsonl`, which is where the mirror rule lives, the
ignore list at `.review/ignore`, and the signers list at `.review/signers`.
Only `sidecars/**` is marked generated. Nothing else appears at the store's
root without a decision here. There are no stores outside this repository, so
the move is a rename, not a migration. ADR-0007, 0014 and 0015 still describe
the sidecars; "the store mirrors the source tree" in them now reads as
"the sidecars directory mirrors the source tree".

## Considered options

- Keep the store flat and put the signers list beside `.reviewignore` at the
  repo root: no restructuring and the same precedent, but legu's files then
  live in two places and each new one is another root dotfile.
- Flat `.review/signers`: the collision and the generated-attribute problem
  above.
