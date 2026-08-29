# legu

Review coverage for a codebase — the reading analogue of test coverage.

`legu` tracks which regions of a repository a human has actually reviewed,
notices when the code under a reviewed region changes, and reports three
numbers: unreviewed, reviewed, stale.

It knows nothing about any programming language. Regions are line ranges;
anchoring is git plus a content hash. It works the same on Clojure, YAML, shell
scripts and SQL migrations.

## Requirements

babashka and git. Nothing else.

## Install

```
cp legu ~/.local/bin/legu   # anywhere on PATH
```

## Use

```
legu mark src/core.clj:40-95           # mark a region reviewed at HEAD
legu mark src/core.clj                 # the whole file
legu ticket src/core.clj:40-95 lgu-01k7  # anchor a ticket reference to a region
legu forget src/core.clj:40-95         # drop that region's state
legu status [<path>]                   # per-file state, for a file or a subtree
legu stale                             # regions that need a re-read
legu next --limit 20                   # what to read next
legu coverage                          # the three numbers
```

Options may appear anywhere on the line, and an unrecognized one is an error
rather than a silently swallowed argument:

- `--json` — machine-readable output
- `--reviewer <name>` — defaults to `git config user.name`
- `--limit <n>` — how many files `next` suggests
- `--help`

## How staleness works

A review record stores the region's line range, the SHA of HEAD at review time,
a hash of the whole file, and a hash of the region's *normalized* content — each
line stripped of leading and trailing whitespace, and nothing more aggressive
than that. A mark also retires every earlier record that now anchors fully
inside the marked range, so re-reading a stale region at the range it now
anchors to leaves one record, not two. A record the mark only partly covers stays: the
part outside was not re-read
([ADR-0013](docs/adr/0013-a-mark-supersedes-only-what-it-contains.md)).

To decide a region's current state, legu:

1. tries to anchor it in the file it was read in — byte-identical file means
   *reviewed* immediately; otherwise it diffs that file as it was at the
   reviewed commit against the working tree (`git diff --no-index -U0`), shifts
   the region across the hunks above it, and re-hashes;
2. if that fails, looks for the block elsewhere in the same file;
3. if that fails, follows the file: the rename git reports since the reviewed
   commit (at a low similarity threshold, so a small file that was renamed
   *and* edited is still matched), and — only when the original path is gone —
   files added since then that contain the reviewed block;
4. reports *stale* at the best location it found, or *missing* if the file is
   gone entirely.

Two consequences worth stating plainly:

- A region that merely **moved** is not stale — whether it shifted, was cut and
  pasted elsewhere in the file, or the file was renamed. Only changed content is.
- A whitespace-only edit inside a region is not a change, because the hash is
  computed on normalized lines.
- Any real change inside a region makes the **whole** region stale. Mark regions
  roughly the size you can hold in your head at once.

A block-move is only trusted when it is unambiguous: exactly one matching block
in the file now, and no twin of it at review time. Two identical blocks where
one was rewritten reports *stale*, which is the honest answer.

A mark relocates only when git reports a **rename**, never a copy. If a file is
copied and the original then edited inside a reviewed region, the original goes
stale and the copy counts as unreviewed — the alternative would let a copy absorb
the mark and hide a real change. The cost is that a rename which also leaves a
new, unrelated file at the old path reports stale rather than following the
move: conservative in the direction that asks for a re-read.

Files are read as bytes and decoded latin-1, so a change to a non-UTF-8 byte is
still a change. State is measured against the **working tree**, not against
HEAD, so an uncommitted edit shows up as stale immediately.

## Emacs

`emacs/` holds `legu.el`, an Emacs 30 front end: a fringe gutter showing which
lines of the file you are looking at have been read, and one keystroke meaning
"everything from where I left off down to here, I have now read". Evil and
Doom users are supported out of the box. See
[emacs/README.md](emacs/README.md).

## Storage

`.review/` at the repo root, one EDN file per source file, mirroring the source
tree — committed alongside the code. Source files are never modified.

```clojure
{:schema 1
 :path "src/core.clj"
 :regions [{:start 40 :end 95
            :commit "a1b2c3…"
            :file-hash "…" :content-hash "…"
            :reviewer "jonas" :timestamp "2026-08-28T01:00:00Z"}]
 :tickets [{:start 40 :end 95 :ticket "lgu-01k7" :commit "a1b2c3…" …}]}
```

One file per source file rather than a single index, so two people reviewing at
once do not conflict on every mark. A file with no line ranges — a binary, or an
empty file — is stored as one opaque region (`:opaque true`) matched on the
file hash alone.

## Eligibility

`legu coverage` counts every tracked file except those matching `.reviewignore`
at the repo root — vendored code, generated files, lockfiles, fixtures.
`.reviewignore` uses gitignore syntax, and git itself does the matching, so
negations and directory patterns behave exactly as you expect.

Binary files (detected by a NUL byte in the first 8 KB) count as one line.

## Ticket references, not prose

`legu ticket` stores a ticket id against a region. The ticket's content and
lifecycle belong to a ticket tracker; legu owns only the anchor, and re-anchors
it exactly the way it re-anchors review regions. A ticket reference is an
anchor of its own: re-marking the lines it sits in retires the review record,
not the reference.

## Outside git

legu still runs without git, so a directory that is not a repository can be
tracked by content hash alone. Three things change: the repo root becomes the
nearest ancestor holding a `.review/` directory (so subdirectories share one
store), the eligible set becomes a walk of the working tree rather than
`git ls-files`, and **`.reviewignore` is inert** — the gitignore matching is
git's, not ours.

## Decisions

The vocabulary is in [CONTEXT.md](CONTEXT.md); the decisions that shaped the
tool, and the alternatives they rejected, are one paragraph each under
[docs/adr/](docs/adr/).

## Known limits

- A region only partly covered by a later mark survives as its own record;
  lines are counted once, but `stale` names the old record's whole range until
  it is re-marked in full or forgotten.
- Content moved between two files that both still exist is stale, not followed.
- A binary file that is renamed *and* rewritten reports `missing`: git has no
  similarity left to match on, so neither has legu.
- Paths containing a newline are rejected; they cannot round-trip the store.
- Marks on files excluded by `.reviewignore`, or on untracked files, are stored
  and warned about, but do not count toward coverage.

## Cost

On a 700-file, 133k-line repository with ~1900 stored regions: `coverage` and
`status` about 1s, `stale` about 1s, `mark` under 1s. Regions in files that have
changed since they were read cost a `git show` and a diff each — with 80 files
edited at once, the same commands take about 2s.
