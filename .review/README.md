# legu's store

This directory is legu's store. It records which regions of this repository a
human has read, so that `legu coverage` can say how much of the code has been
reviewed, and how much of what was reviewed has changed since.

legu wrote this file when it created the store. It is yours now: edit it
freely, legu will never touch it again.

## What is in here

- `sidecars/` — one file per source file, mirroring the source tree, holding
  that file's review records and ticket references, one JSON object per line.
- `ignore` — the files that do not count toward coverage: vendored code,
  generated files, lockfiles, fixtures. Gitignore syntax, matched by git
  itself, so it is inert outside a git repository.
- `signers` — the keys whose signatures this store trusts. Its presence is
  what makes every review record here a signed one.

The sidecars arrive with the first mark. `ignore` and `signers` appear when
you add them.

## The CLI owns the sidecars

Nothing but the `legu` command line tool writes under `sidecars/`. Use `legu
mark` to record a region as read and `legu forget` to drop one; `legu --help`
lists the rest. Editors and agents are welcome to read these files, but every
change to one goes through the CLI, which is the only thing that knows how a
record is superseded and re-anchored as the code moves.

`ignore` and `signers` are yours to edit by hand.

## It is committed on purpose

Review state belongs to the repository rather than to one checkout, so this
directory is committed alongside the code. To keep the sidecars out of your
diffs, mark them generated in `.gitattributes` at the repository root:

    .review/sidecars/** linguist-generated=true gitlab-generated=true

GitHub and GitLab then collapse them in review views. Files at this
directory's root stay in full, which is what you want for `signers`.

<https://github.com/UniSoma/legu>
