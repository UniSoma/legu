# legu

Review coverage for a codebase — the reading analogue of test coverage.

`legu` tracks which regions of a repository a human has actually reviewed,
notices when the code under a reviewed region changes, and reports three
numbers: unreviewed, reviewed, stale.

It knows nothing about any programming language. Regions are line ranges;
anchoring is git plus a content hash. It works the same on Clojure, YAML, shell
scripts and SQL migrations.

## Requirements

babashka 1.13.220 or newer, and git. Nothing else.

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
legu status [<path>] [--gaps]          # the three numbers, then per-file state
legu regions src/core.clj              # current anchors and their provenance
legu stale                             # regions that need a re-read
legu next --limit 20                   # what to read next, in directory order
legu next --order cochange             # ...ordered by what changes with what you read
legu coverage                          # the three numbers
```

Options may appear anywhere on the line, and an unrecognized one is an error
rather than a silently swallowed argument:

- `--json` — machine-readable output
- `--reviewer <name>` — defaults to `git config user.name`
- `--limit <n>` — how many files `next` suggests
- `--order <dir|cochange>` — which question `next` answers (below)
- `--gaps` — `status` lists only files with something left to read
- `--help`
- `--version` — the version and the store schema (the `:schema` every sidecar
  carries) this legu writes, which is what a client needs before it trusts
  what it reads out of `.review/`:

```
$ legu --version
legu 0.4.1 (store schema 2)

$ legu --version --json
{
  "version" : "0.4.1",
  "schema" : 2
}
```

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

## What to read next

`legu next` lists the files with something left to read: a heading saying how
many of them are on screen, how many have gaps and which order they are in,
then one row per file with its unread and stale line counts and the lines left
to read. The two orderings answer different questions, and the default is
`dir`:

```
legu next                    # same as --order dir
legu next --order cochange
```

**`dir`** walks the tree in directory order, which keeps a reader inside one
part of the codebase for a sitting. Reach for it when you are reading a
subsystem through, or when you want the queue to be the same every time —
it depends on nothing but the tree, so it is stable and it works without git.

**`cochange`** answers "given what I have already read, what changes alongside
it?". Every file with a gap is scored by the number of commits in which it
changed together with a file that already carries a reviewed line, current or
stale. Files with a score come first, highest first; the rest follow in
directory order, which is also how ties break. A file never scores itself: a
commit touching one file you have read and nothing else says nothing about
what to read next. Reach for it when you have read some of a system and want
the code that moves with it — the callers, the tests, the config that has to
change in step — rather than the code that happens to sit next to it.

With nothing marked yet the two orderings are identical: there is nothing to
have co-changed with.

The signal is one `git log` over the history and nothing else. legu knows no
language here, so a call graph it cannot see still shows up if the two files
keep landing in the same commit. Merge commits list no files and so contribute
nothing, which is what you want: a merge would otherwise read as every file on
the branch changing together. `--order cochange` needs git and says so if
there is none; plain `next` still works without it.

`--json` carries the same `next` array, in the order you asked for.

## Inspect one file

`legu regions <path>` resolves the review records and ticket references that
currently anchor in one file. Editors can use it without computing coverage
for the rest of the repository.

```json
{
  "path": "src/core.clj",
  "eligible": true,
  "condition": "present",
  "total": 169,
  "opaque": false,
  "complete": true,
  "regions": [{
    "start": 40,
    "end": 95,
    "state": "reviewed",
    "reason": null,
    "moved": true,
    "opaque": false,
    "original": {
      "path": "src/old-core.clj",
      "start": 38,
      "end": 93,
      "commit": "a1b2c3...",
      "reviewer": "Ada",
      "timestamp": "2026-08-28T01:00:00Z"
    }
  }],
  "tickets": [{
    "start": 52,
    "end": 52,
    "state": "reviewed",
    "reason": null,
    "moved": false,
    "opaque": false,
    "ticket": "lgu-01k7",
    "original": {
      "path": "src/core.clj",
      "start": 52,
      "end": 52,
      "commit": "a1b2c3...",
      "timestamp": "2026-08-28T01:00:00Z"
    }
  }]
}
```

Current `start` and `end` values are null when a record is missing. The
`original` object retains its recorded bounds. Overlapping review records stay
separate, and lines outside the returned records are unreviewed.

Text and binary files use `condition: "present"`. Missing and unreadable files
use their condition name and report `total: 0`. Empty and binary files have
`total: 1`, `opaque: true`, and null bounds. A tracked missing or unreadable
file remains eligible. An existing ignored or untracked file has
`eligible: false` and an `exclusion-reason`, but still returns its records.

An unreadable sidecar makes `complete` false. The command still exits 0, lists
the sidecar under repository-relative `errors`, and writes the warning to
stderr. A directory, a path outside the repository, or an unknown missing path
is an error. Without `--json`, the command prints the same anchors, states,
reasons, provenance, ticket references, and completeness.

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
{:schema 2
 :regions [
  {:start 40 :end 95
   :reviewer "jonas" :timestamp "2026-08-28T01:00:00Z"
   :commit "a1b2c3…"
   :file-hash "…"
   :content-hash "…"}
 ]
 :tickets [
  {:start 52 :end 52
   :ticket "lgu-01k7" :timestamp "2026-08-28T01:00:00Z"
   :commit "a1b2c3…"
   :file-hash "…"
   :content-hash "…"}
 ]}
```

The layout is fixed so that git shows a change to the store as the lines of
one record and nothing else. Every record is self-contained: its region on one
line, who read it and when on the next, then the commit and each full hash on
a line of its own. Collection delimiters sit on lines of their own, so adding
or removing a record never touches its neighbours, and two people editing
different records merge cleanly while two edits to the same record are a
conflict git shows you. Records are sorted by region, ties broken by their
remaining fields, so the same state is always the same bytes. The source path
is not stored: the sidecar's own location says it. An opaque record has no
line range and no content hash, only `:opaque true` and the file hash. Both
collections are always written, and a sidecar with nothing left in it is
removed. Sidecars of any other schema are refused, not migrated
([ADR-0014](docs/adr/0014-fixed-layout-sidecars.md)).

legu skips a sidecar it cannot parse — most often one with a merge conflict
left in it — instead of dying on it. `status`, `stale`, `next` and `coverage`
answer for every other file and exit 0; `mark`, `ticket` and `forget` leave that
sidecar alone and do their work everywhere else. Every command names what it
skipped on stderr and adds an `errors` key to its `--json`:

```json
{"files": [...], "tickets": [...],
 "errors": [{"file": ".review/src/core.clj.edn",
             "reason": "not a review record"}]}
```

Paths there are relative to the repo root, one entry per file, and the key is
absent when there is nothing to report. A file whose sidecar legu cannot read
leaves the counts entirely: calling it never read would send `next` back to a
file you have already read. The one command that still refuses is a write to
the unreadable sidecar itself: writing it would drop the state it still holds.

One file per source file rather than a single index, so two people reviewing at
once do not conflict on every mark. A file with no line ranges — a binary, or an
empty file — is stored as one opaque region (`:opaque true`) matched on the
file hash alone.

## Eligibility

`legu coverage` prints the three numbers over eligible lines — never read,
read, stale — as three rows on one bar scale, which is the block `legu status`
opens with. It counts every tracked file except those matching `.reviewignore`
at the repo root — vendored code, generated files, lockfiles, fixtures.
`.reviewignore` uses gitignore syntax, and git itself does the matching, so
negations and directory patterns behave exactly as you expect.

Binary files (detected by a NUL byte in the first 8 KB) and empty files count
as one line each.

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

## Tests

```
bb test/cli_test.clj
```

The CLI suite records what `legu` does with a command line: how each option is
parsed and where it may appear, how many arguments each command takes, and the
exit code and message behind every error. It needs babashka and git, builds its
own scratch repositories, and exits non-zero when any assertion fails.

The Emacs package has its own ERT suite, documented under
[emacs/README.md](emacs/README.md#tests).

## Known limits

- A region only partly covered by a later mark survives as its own record;
  lines are counted once, but `stale` names the old record's whole range until
  it is re-marked in full or forgotten.
- Content moved between two files that both still exist is stale, not followed.
- `--order cochange` reads the history under each file's current path, so a
  file's score starts at its rename: the commits it changed in under its old
  name do not count.
- A binary file that is renamed *and* rewritten reports `missing`: git has no
  similarity left to match on, so neither has legu.
- Paths containing a newline are rejected; they cannot round-trip the store.
- Marks on files excluded by `.reviewignore`, or on untracked files, are stored
  and warned about, but do not count toward coverage.
- A mark cannot retire a record held in a sidecar it could not read, so that
  record survives as a ghost until the sidecar is fixed. The mark still lands,
  and names the sidecar it skipped.

## Cost

On a 700-file, 133k-line repository with ~1900 stored regions: `coverage` and
`status` about 1s, `stale` about 1s, `mark` around a tenth of a second. Regions
in files that have changed since they were read cost a `git show` and a diff
each — with 80 files edited at once the read commands take about 2s, while
`mark` does not move: it anchors only the records that could be sitting in the
file it marks, never the whole store.

`--order cochange` adds one `git log` over the whole history. On a clone of
[redis](https://github.com/redis/redis) — 13,281 commits, 2009 to 2026 — with
one file marked, `next` takes 0.85s and `next --order cochange` 1.17s: the
ordering costs about 0.33s, most of it the log itself. The history is not
bounded: at that size the whole of it stays well under the second the ordering
is allowed.
