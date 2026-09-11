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

## Shell completion

legu completes command names, the subcommands of `key`, the options each
command takes, and the values `--order` accepts. It builds them from the same
table that parses the command line, so they stay right as legu grows options.

Add one line to your shell's init file.

bash, in `~/.bashrc`:

```
source <(legu org.babashka.cli/completions snippet --shell bash)
```

zsh, in `~/.zshrc`, below the `compinit` call:

```
source <(legu org.babashka.cli/completions snippet --shell zsh)
```

fish reads completions from a file instead. Run this once — fish does not
create the directory itself:

```
mkdir -p ~/.config/fish/completions && legu org.babashka.cli/completions snippet --shell fish > ~/.config/fish/completions/legu.fish
```

Open a new shell, then type `legu ` and press TAB.

`--shell` also emits snippets for `powershell` and `nushell`. Those two ship
untested: legu is verified against bash, zsh and fish.

## Use

```
legu mark src/core.clj:40-95           # mark a region reviewed as it stands now
legu mark src/core.clj                 # the whole file
legu ticket src/core.clj:40-95 lgu-01k7  # anchor a ticket reference to a region
legu forget src/core.clj:40-95         # drop that region's state
legu status [<path>] [--gaps]          # the three numbers, then per-file state
legu regions src/core.clj              # current anchors and their provenance
legu stale                             # regions that need a re-read
legu next --limit 20                   # what to read next, in directory order
legu next --order cochange             # ...ordered by what changes with what you read
legu coverage                          # the three numbers
legu key init                          # create this machine's signing key
legu key show                          # print the key's line for a signers list
legu key add                           # add that line to .review/signers
legu verify [<path>]                   # report records whose signature fails
```

Each option belongs to the one command that reads it, and stands after that
command. Giving it to another command is an error naming the option, and so is
putting it before its own; an option legu does not have at all is a third. `legu
status --limit 3` answers `status does not take --limit`, where legu used to
accept the line and ignore the flag:

- `mark --reviewer <name>` — defaults to `git config user.name`; refused in a
  signed store, which takes the name from `.review/signers`
- `next --limit <n>` — how many files `next` suggests
- `next --order <dir|cochange>` — which question `next` answers (below)
- `status --gaps` — `status` lists only files with something left to read

Three options are legu's own rather than any command's, and those may still
appear anywhere on the line:

- `--json` — machine-readable output
- `--help` — the commands and these three; `legu <command> --help` adds the
  arguments and options of one command
- `--version` — the version and the store schema (the `schema` every sidecar's
  first line carries) this legu writes, which is what a client needs before it
  trusts what it reads out of `.review/`:

```
$ legu --version
legu 0.5.0 (store schema 4)

$ legu --version --json
{
  "version" : "0.5.0",
  "schema" : 4
}
```

## How staleness works

A review record stores the region's line range, the SHA of HEAD at review time,
a hash of the whole file, and a hash of the region's *normalized* content — each
line stripped of leading and trailing whitespace, and nothing more aggressive
than that. A mark also retires every earlier record that now anchors fully
inside the marked range, so re-reading a stale region at the range it now
anchors to leaves one record, not two. A record the mark only partly covers
stays: the part outside was not re-read
([ADR-0013](docs/adr/0013-a-mark-supersedes-only-what-it-contains.md)).

To decide a region's current state, legu:

1. tries to anchor it in the file it was read in — byte-identical file means
   *reviewed* immediately; otherwise it diffs that file as it was at the
   reviewed commit against the working tree (`git diff -U0`, one call per
   commit for every file that needs it), shifts the region across the hunks
   above it, and re-hashes;
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
then one row per file with its unreviewed and stale line counts and the lines left
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

The store is `.review/` at the repo root, committed alongside the code. It
holds everything legu owns: one JSON Lines sidecar per source file under
`.review/sidecars/`, mirroring the source tree (`.review/sidecars/<path>.jsonl`),
the ignore list at `.review/ignore` and the signers list at `.review/signers`
([ADR-0017](docs/adr/0017-everything-legu-owns-lives-under-the-store.md)).
Source files are never modified.

```jsonl
{"schema":4}
{"start":40,"end":95,"reviewer":"jonas","timestamp":"2026-08-28T01:00:00Z","commit":"a1b2c3…","file-hash":"…","content-hash":"…"}
{"start":52,"end":52,"ticket":"lgu-01k7","timestamp":"2026-08-28T01:00:00Z","commit":"a1b2c3…","file-hash":"…","content-hash":"…"}
```

The first line is the header; every line after it is one record, so git shows
a mark, a supersede or a forget as one changed line and nothing else. A line
with a `reviewer` is a review record and a line with a `ticket` is a ticket
reference. Keys come in a fixed order with no whitespace: the region, then who
and when, then the commit and the two full hashes, and in a signed store the
signature last, so what you scan sits at the front of the line and the hashes
are a tail the eye skips. Review records come first, then ticket references,
each sorted by region with ties broken by their remaining fields, so the same
state is always the same bytes and two people editing different records merge
cleanly while two edits to the same record are a conflict git shows you.
Timestamps are whole seconds. The source path is not stored: the sidecar's own
location says it. An opaque record has no line range and no content hash, only
`"opaque":true` and the file hash. A sidecar with nothing left in it is
removed. Sidecars of any other schema are refused, not migrated
([ADR-0015](docs/adr/0015-jsonl-sidecars-one-record-per-line.md)). The
committed `.gitattributes` marks `.review/sidecars/**` as generated, which
collapses sidecars in GitHub and GitLab review views. Files at the store's
root, such as the ignore list and the signers list, show in full.

legu skips a sidecar it cannot parse — most often one with a merge conflict
left in it — instead of dying on it. One line that does not parse makes the
whole sidecar unreadable: skipping the line would read around a conflict by
dropping the records inside it. `status`, `stale`, `next` and `coverage`
answer for every other file and exit 0; `mark`, `ticket` and `forget` leave that
sidecar alone and do their work everywhere else. Every command names what it
skipped on stderr and adds an `errors` key to its `--json`:

```json
{"files": [...], "tickets": [...],
 "errors": [{"file": ".review/sidecars/src/core.clj.jsonl",
             "reason": "not a review record"}]}
```

Paths there are relative to the repo root, one entry per file, and the key is
absent when there is nothing to report. A file whose sidecar legu cannot read
leaves the counts entirely: calling it unreviewed would send `next` back to a
file you have already read. The one command that still refuses is a write to
the unreadable sidecar itself: writing it would drop the state it still holds.

One file per source file rather than a single index, so two people reviewing at
once do not conflict on every mark. A file with no line ranges — a binary, or an
empty file — is stored as one opaque region (`"opaque":true`) matched on the
file hash alone.

## Eligibility

`legu coverage` prints the three numbers over eligible lines — unreviewed,
reviewed, stale — as three rows on one bar scale, which is the block `legu status`
opens with. It counts every tracked file except the store's own files and
those matching the ignore list, `.review/ignore`: vendored code, generated
files, lockfiles, fixtures. The ignore list uses gitignore syntax, and git
itself does the matching, so negations and directory patterns behave exactly
as you expect.

Binary files (detected by a NUL byte in the first 8 KB) and empty files count
as one line each.

## Signing

In a signed store, each review record carries an Ed25519 signature made with
the key of the person who marked it, so a reader can tell who made a record
([ADR-0016](docs/adr/0016-signed-review-records.md)). A store is signed when it
has a signers list, `.review/signers`. A store without one needs no key and
behaves as it always has.

To turn signing on, each reviewer creates a key once per machine and adds it to
the signers list, and the repository commits the list:

```
legu key init             # once per machine
legu key add              # list the key in .review/signers
git add .review/signers && git commit -m "Sign reviews"
```

A reviewer who cannot push to the repository runs `legu key show` and hands the
line it prints to someone who can.

### Keys

`legu key init` writes two files to `$XDG_CONFIG_HOME/legu/`, or to
`~/.config/legu/` when `XDG_CONFIG_HOME` is unset:

- `key` holds the 32-byte Ed25519 seed, base64 on one line. legu creates it with
  mode 0600, so only its owner can read it. The key has no passphrase, so a mark
  never prompts.
- `key.pub` holds the 32-byte public key, base64 on one line. `key show` and
  `key add` read the public key from this file.

`key init` refuses to run when `key` exists, so a second run cannot destroy the
key a signers list names.

`legu key show` prints the key's signers-list line: the public key, one space,
then `git config user.name`. `legu key add` appends that line to
`.review/signers`, and creates `.review/` and the file when they are missing. A
second `key add` with the same line changes nothing. When the list already has
the key under another name, `key add` fails and names that name, because one key
belongs to one reviewer. Both commands fail with no key, naming `legu key init`,
and with no `git config user.name`.

With `--json`, each command prints an object:

- `key init`: `private-key-file` and `public-key-file`, the two absolute paths, and
  `public-key`.
- `key show`: `public-key`, `reviewer`, and `line`, the line itself.
- `key add`: `file` (always `.review/signers`), `public-key`, `reviewer`, and
  `added`, which is false when the line was already there.

### The signers list

`.review/signers` lists one key per line: the public key in base64, one space,
then the reviewer name to the end of the line.

```
# Reviewers whose marks this repository trusts
8EJFVMYkblOCNPJAWEwiIPxVq3CWljggnjD0+kUfQ4s= Ana Lima
Tf/LAC9t33pEG+PpOcb30SyBnKikfUXeSfkNt0KTaNU= Ana Lima
```

legu skips blank lines and lines that start with `#`. A key appears at most
once. A name can appear on several lines, one for each machine its reviewer
signs from. The list is committed and shows in full in review views, so a change
to who may sign is a diff to one file.

### Signed review records

In a signed store, `legu mark` signs every review record it writes. Before it
writes anything, it checks that it can:

- `mark` needs a local key. When `key` or `key.pub` is missing, it fails and
  names `legu key init`.
- The signers list must have the key in `key.pub`. When it does not, `mark`
  fails and names `legu key add`.
- `mark` takes the reviewer name from the key's line in the signers list, so it
  does not need `git config user.name`. It refuses `--reviewer`, because a
  record under any other name would fail verification.

The signature is Ed25519 over the UTF-8 bytes of the line `legu-review-record`,
one newline, and then the record's line exactly as the sidecar stores it,
without the `signature` key. No newline follows the record line. For the review
record in the Storage example, the signed bytes are:

```
legu-review-record
{"start":40,"end":95,"reviewer":"jonas","timestamp":"2026-08-28T01:00:00Z","commit":"a1b2c3…","file-hash":"…","content-hash":"…"}
```

The domain line keeps a signature over a legu record from passing as a
signature over anything else. The sidecar stores the 64 signature bytes in
base64 under `signature`, the last key on the line, so a mark is still a
one-line change:

```jsonl
{"start":40,"end":95,"reviewer":"jonas",…,"content-hash":"…","signature":"…"}
```

Any change to the record line, its key order included, breaks the signature, so
a change to the line's layout is a change to the sidecar schema. `forget` and a
superseding `mark` remove whole records, and the records they leave keep their
signatures. Ticket references carry no signature, so `legu ticket` needs no key.
In an unsigned store, `mark` reads no key and writes no signature.

### Verify

`legu verify` checks every review record in the store against the signers
list. `legu verify <path>` checks only the records of that file, or of the
files under that directory. It reads public keys from `.review/signers` and
needs no local key, so a CI job can run it.

Each review record gets one outcome:

- `valid`: a key the signers list binds to the record's reviewer made the
  signature over the record as it stands.
- `bad-signature`: the signature is not 64 bytes of base64, or no key listed
  for the reviewer made it. An edit to any field of the record, a hash
  included, lands here.
- `unlisted-signer`: the signers list binds no key to the record's reviewer.
- `name-mismatch`: a listed key made the signature, but the signers list binds
  that key to another name.
- `unsigned`: the record has no signature. Records written before the store
  had a signers list land here, and re-marking the region signs it.

A record does not say which key signed it. So a listed reviewer who marks from
a second machine whose key is not in the list also gets `bad-signature`, and
`legu key add` on that machine fixes it.

The output lists each record that is not valid on one line: the sidecar, the
region, the reviewer, the outcome and the reason. Each line of the signers list
that does not parse gets a line with its line number. A count ends the output:

```
$ legu verify
.review/sidecars/src/core.clj.jsonl  src/core.clj:40-95  jonas  bad-signature  (no key listed for jonas made this signature)
12 review records, 1 not valid
```

`verify` exits 1 when a record is not valid, a sidecar cannot be read, or a
line of the signers list does not parse, and 0 otherwise, so CI can gate on it.
In an unsigned store it prints `the store is not signed: there is no
.review/signers` and exits 0.

With `--json`, `verify` prints an object:

- `signed`: false in an unsigned store, where both arrays are empty.
- `records`: every review record checked, valid ones included, each with
  `file` (its sidecar), `path`, `start` and `end` (absent for an opaque
  record), `reviewer`, `outcome` (one of the five above) and `reason` (null
  when valid).
- `signers-errors`: every line of `.review/signers` that does not parse, with
  `line` (counted from 1), `text` and `reason`.
- `errors`: the sidecars `verify` could not read, as every command reports them.

`status`, `stale`, `next`, `regions` and `coverage` never check signatures.
They count a record that fails `verify` as reviewed or stale like any other,
so a verification problem never changes the numbers. Ticket references carry
no signature, and `verify` skips them.

A signature proves only that a key in the list made the record. A listed key
is as trustworthy as the commit that listed it: anyone who can push can add a
key to `.review/signers` under any name. git's `allowed_signers` file has the
same limit. Review a change to `.review/signers` the way you review code.

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
`git ls-files`, and **`.review/ignore` is inert** — the gitignore matching is
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

It also drives shell completion through the shells themselves, and so needs
bash, zsh and fish on PATH: zsh runs interactively on a pseudo-terminal with the
snippet in its `.zshrc` and is sent a real TAB, bash sources the snippet and is
asked what it would have offered, and fish is asked through `complete -C`
against the file the section above installs. A shell that is missing fails the
suite rather than passing quietly, since completion is then unchecked.

`bb test` runs this suite and the Emacs one, and `bb lint` runs clj-kondo and
checks that prose stays within 85 columns.

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
- Marks on files excluded by `.review/ignore`, or on untracked files, are stored
  and warned about, but do not count toward coverage.
- A mark cannot retire a record held in a sidecar it could not read, so that
  record survives as a ghost until the sidecar is fixed. The mark still lands,
  and names the sidecar it skipped.
- `verify` trusts `.review/signers` as committed: a listed key is only as
  trustworthy as the commit that added it. A listed reviewer who marks from a
  machine whose key is not listed gets `bad-signature` until that machine runs
  `legu key add`.

## Cost

On a 700-file, 133k-line repository with ~1900 stored regions: `coverage` and
`status` about 1s, `stale` about 1s, `mark` around a tenth of a second. Files
that have changed since they were read are diffed against the commits their
regions cite, one `git diff` per commit, while `mark` diffs only the records
that could be sitting in the file it marks, never the whole store.

`--order cochange` adds one `git log` over the whole history. On a clone of
[redis](https://github.com/redis/redis) — 13,281 commits, 2009 to 2026 — with
one file marked, `next` takes 0.85s and `next --order cochange` 1.17s: the
ordering costs about 0.33s, most of it the log itself. The history is not
bounded: at that size the whole of it stays well under the second the ordering
is allowed.
