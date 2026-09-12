# Everything legu owns lives under `.review/`

Until now `.review/` held sidecars only and mirrored the source tree exactly,
while the ignore list sat at the repo root as `.reviewignore`. The signers
list of ADR-0016 is a second file that is neither a sidecar nor state, and a
flat `.review/signers` would collide with a source directory named `signers/`
and be hidden by the `.gitattributes` rule that collapses the whole store in
review views, when it is the one file that must be read in review. The store
is now the single directory for everything legu owns: sidecars under
`.review/sidecars/<path>.jsonl`, which is where the mirror rule lives, the
ignore list at `.review/ignore`, the signers list at `.review/signers`, and a
`README.md` saying what the directory is. Only `sidecars/**` is marked
generated. Nothing else appears at the store's root without a decision here.
There are no stores outside this repository, so the move is a rename, not a
migration. ADR-0007, 0014 and 0015 still describe the sidecars; "the store
mirrors the source tree" in them now reads as "the sidecars directory mirrors
the source tree".

The README is the one member that is not state. legu writes it when it creates
the store, from the same call that makes the directory, and never reads it or
writes it again: a store that already exists does not grow one, and an edited
one is left alone. A directory a stranger finds in a diff should say what it is
without a command being run, and the alternative — a `legu init` command whose
only job was to write it — would have been ceremony before the first mark, for
a file legu can write the moment it has somewhere to put it.

## Considered options

- Keep the store flat and put the signers list beside `.reviewignore` at the
  repo root: no restructuring and the same precedent, but legu's files then
  live in two places and each new one is another root dotfile.
- Flat `.review/signers`: the collision and the generated-attribute problem
  above.
