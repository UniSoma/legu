# legu.el

Emacs front end for [legu](../README.md), the review coverage tool.

It is a fringe gutter plus one keystroke. The gutter says which lines of the
file you are looking at are reviewed, and which you read but which have since
changed. `C-c r r` means *everything from where I left off down to
here, I have now read*.

Nothing here writes `.review/`. Every mutation goes through the `legu` command
line tool, which stays the single owner of review state.

## Requirements

- Emacs 30.1 or newer
- `transient` 0.7.2 — the version bundled with Emacs 30 already satisfies this,
  so nothing is downloaded
- the `legu` executable on `exec-path`, and `git`. legu.el speaks to legu
  0.4.1 or newer

## Install

```elisp
(add-to-list 'load-path "/path/to/legu/emacs")
(require 'legu)

(global-legu-mode 1)
(repeat-mode 1)   ; makes the reading loop  C-c r r  then  n r n r
```

`global-legu-mode` turns the mode on only in files under a directory that
already has a `.review/` store. A repository that has never run `legu` costs
nothing on visit — no subprocess, no `git` call, no mode.

## The daily loop

```
C-c r l          the queue: three coverage numbers, stale regions, what to read next
n n RET          visit a file at its first gap
… read 60 lines …
C-c r r          mark from the frontier down to point
n r n r          read, mark, read, mark
```

Two keystrokes per chunk after the first. When a region you read goes stale:

```
C-c r ]          jump to it
C-c r s          the diff since the commit you read it at, in a side window
r                re-mark it and put the windows back
```

## Keys

All under `C-c r` (`legu-prefix-key`), and only in buffers where `legu-mode`
is on.

| Key | Command | |
|---|---|---|
| `r` | `legu-mark` | frontier → point; the region if there is one; `C-u` whole file |
| `R` | `legu-mark-file` | the whole file |
| `SPC` | `legu-set-frontier` | I am reading from here |
| `n` `p` | `legu-next-gap` `legu-previous-gap` | next unreviewed or stale line here |
| `]` `[` | `legu-next-stale` `legu-previous-stale` | next stale region here |
| `s` | `legu-diff-stale` | what changed since I read it (`C-u` for ediff) |
| `.` | `legu-describe-region` | current state, provenance and tickets at point |
| `t` `T` | `legu-ticket` `legu-visit-ticket` | anchor / open a ticket id |
| `k` | `legu-forget` | drop this region's state |
| `l` `J` | `legu-list` `legu-next-file` | the queue / straight to the next file |
| `c` `g` | `legu-coverage` `legu-refresh` | the three numbers / repaint (`C-u` re-runs legu) |
| `h` `f` | `legu-toggle-highlights` `legu-list-failures` | |
| `?` | `legu-dispatch` | the transient menu |

## What you see

The gutter glyph carries the state; the background is reserved for the alarm.

| | GUI fringe | terminal / margin | background |
|---|---|---|---|
| unreviewed | nothing | nothing | none |
| reviewed | solid bar | `│` | none |
| stale | dashed bar | `!` | tinted |
| ticket anchored | dot, first line only | `*` | — |
| unverified | thin dashes | `:` | none |
| reading frontier | triangle | `>` | — |

A fully unreviewed file looks exactly like a file without the mode, which is the
right visual cost for the buffers you open to grep something.

The mode line shows repo-wide percent reviewed and this buffer's stale count:
` legu 61%▪3`. The percent is floored, so it never rounds an unreviewed line up
to reviewed. A trailing `?` means legu cannot currently vouch for what is drawn; `!`
means the store is unreadable; `—` means the file is outside the eligible set.

## The dired column

In a dired buffer under a repository with a `.review/` store,
`global-legu-mode` turns on `legu-dired-mode`, which draws a column before
each filename:

```
  48% 2%   src
  72% 3%?  src/a.el
  100%     README.md
  —        docs
```

Reviewed percent first, floored; then stale percent, ceilinged and blank at
zero. Unreviewed is the remainder. Both rounding errors point at remaining
work, never away from it. A directory sums the eligible files beneath it,
line for line, so a big unreviewed file weighs what it costs. `—` is a file
outside the eligible set, or a directory with none beneath it. `?` says the
file — or a file somewhere under the directory — is newer than the snapshot,
so the numbers describe a version you have since changed; the debounced
refresh replaces them.

Everything comes from the cached snapshot: opening a dired buffer never runs
the CLI, and the column redraws when a snapshot lands. Inserted
subdirectories and `dired-subtree` sections get the column too, and it
survives `dired-hide-details-mode`. TRAMP and dirvish buffers are left alone.
The column is read-only — marking happens in the file or from the queue.
The faces are the gutter's own, so the column doubles as its legend:
reviewed in the gutter's green, stale in the warning face, `?` and `—`
dimmed. `100%` is bold. There are no colour thresholds — coverage is two
numbers, not a score. `legu-dired-column` set to nil turns it off.

## How it stays fast, and honest

Four tiers, with one rule binding them: **local computation may confirm
"reviewed, in place"; it may never pronounce "stale", "moved" or "missing".**
Those verdicts come only from the CLI.

`legu-describe-region` runs `legu regions` for the saved file. It reports every
overlapping review record at point, with each record's current state, reason,
recorded location, reviewer, timestamp and commit. It also reports independent
ticket references at point. A buffer edit or a newer describe request discards
an older asynchronous answer.

1. **The sidecar and a file hash.** Opening a file reads
   `.review/sidecars/<path>.jsonl` and hashes the file — no subprocess at
   all. A record whose stored `file-hash` still matches is exactly the case the
   CLI's own anchoring answers immediately, so it can be painted with no
   process. A file whose every record matches this way is the one case that
   runs nothing else.
2. **A per-file query.** When the sidecar at the file's current path cannot
   account for it — there is none, or a record's hash no longer matches — and
   no trusted snapshot already covers it, one `legu regions <path> --json`
   runs for that file alone, asynchronously, and paints the reviewed and
   stale regions and the ticket lines at their current anchors. It is the CLI, so unlike
   the sidecar pass above it may pronounce stale, moved or missing. This is
   what paints a file whose regions were read under a previous name, before
   any snapshot has run. The answer is dropped if the buffer changed since it
   was asked for, or if a newer answer or a trusted snapshot has overtaken it;
   an incomplete one paints what was resolved and keeps the unverified
   indicator. The same query runs after save and after revert, under the same
   condition. Once a snapshot is cached, most opens are covered by it and this
   tier is skipped too.
3. **A repository snapshot**, from one `legu status --json` and one
   `legu stale --json`, run asynchronously and cached. `legu coverage` and
   `legu next` are never invoked: both are arithmetic over the same rows, and
   an ERT test asserts the derived numbers equal the CLI's own, row for row.
   That halves the work a refresh costs.
4. **An optimistic patch** while a mark is in flight, drawn in the unverified
   style until legu confirms it.

A snapshot may only pronounce on a file it is newer than. Without that guard
the union paints a lie: edit inside a region you had read, save, and a
snapshot from a minute ago would still call it read.

The first CLI run against a repository is preceded by one
`legu --version --json`. A legu older than the one this package speaks to, or
one writing a store schema it does not read, says so in the echo area once
per repository. Nothing waits on that answer: an unrecognised legu is still
driven, just with the warning standing.

Nothing ever blocks Emacs. Refreshes are debounced, coalesced, and never
overlap a write; writes are serialized per repository, because the CLI's
supersede pass can rewrite sidecars other than the one you named.

## Unsaved buffers

legu reads the file on disk, so a mark in a modified buffer would record
content you never read. On the first change the indicators dim, the mode line
shows `?`, and no process runs. `legu-save-before-mark` decides what a
mutation does then: `t` saves first (the default), `ask` prompts, `nil`
refuses. There is no setting that acts on a modified buffer silently.

## Configuration worth knowing

| Variable | Default | |
|---|---|---|
| `legu-executable` | `"legu"` | |
| `legu-prefix-key` | `"C-c r"` | |
| `legu-save-before-mark` | `t` | `t`, `ask` or `nil` |
| `legu-indicator-style` | `fringe` | or `margin`, `face-only` |
| `legu-frontier-max` | `400` | confirm above this many lines |
| `legu-watch-store` | `t` | notice other people's marks landing |
| `legu-dired-column` | `t` | the coverage column in dired |
| `legu-ticket-visit-function` | `knot show` | how `T` opens a ticket |
| `legu-header-line-mode` | off | a one line map of the file |
| `legu-evil-integration` | `t` | bind the queue and diff buffers for evil |
| `legu-evil-source-motions` | `t` | `]r` `[r` `]g` `[g` in source buffers |

Leave `legu-reviewer` unset in a signed store, one with a `.review/signers`.
Emacs passes it to `legu mark` as `--reviewer`, and a signed store refuses
`--reviewer` because it takes the name from the signers list.

## Doom Emacs and evil

Install it the way you install any local package:

```elisp
;; ~/.doom.d/config.el
(add-to-list 'load-path "~/src/legu/emacs")
(use-package! legu
  :config
  (global-legu-mode 1)
  (repeat-mode 1))
```

Evil support loads itself when evil is present; `legu-evil-integration`
turns it off. It is not cosmetic. `legu-list-mode` derives from
`compilation-mode`, so without it evil-collection's compile bindings reach
the queue through the parent keymap and `RET` runs `compile-goto-error`
instead of `legu-list-visit` — which reads the row's text properties, and so
survives a path containing a colon — while `gr` runs `recompile` on a buffer
no compilation produced and every action key (`o r s c x a i d p`) is bound
to `ignore`.

In source buffers nothing changes: `C-c r` works in normal state, and two
pairs of bracket motions are added (`legu-evil-source-motions` turns them
off).

| Key | | |
|---|---|---|
| `]r` `[r` | next / previous stale region | source buffers |
| `]g` `[g` | next / previous gap | source buffers |

In the queue buffer, motions stay motions and the actions take the keys a
read-only buffer frees up:

| Key | Command | |
|---|---|---|
| `RET` `gd` | `legu-list-visit` | |
| `o` `go` | `legu-list-visit-other-window` | |
| `gj` `gk`, `]]` `[[` | next / previous row | evil-collection's, kept |
| `r` | `legu-list-mark` | also in visual state, for several rows at once |
| `d` | `legu-list-diff` | |
| `a` | `legu-list-ticket` | anchor a ticket |
| `x` | `legu-list-forget` | |
| `c` `gf` | `legu-coverage` / cycle the filter | |
| `gr` | refresh | |
| `?` `g?` | `legu-dispatch` | |
| `q` | quit | |

And in the diff buffer: `r` re-marks, `=` runs ediff, `q` quits and puts the
windows back.

Three of those choices are forced, and worth knowing about:

- **Diff is `d`, not the `s` the Emacs keymap uses.** Doom enables
  evil-snipe, whose minor mode map outranks every major mode's, so `s`, `S`,
  `f` and `t` in any buffer are snipes and no keymap can take them back.
- **`?` opens the transient** instead of searching backwards, which is the
  bargain evil-collection already strikes in magit.
- **`q` in the diff buffer is caught by a command remap.** evil-collection
  binds it to `quit-window` from a minor mode map; plain `quit-window` would
  quit without restoring the window configuration, which is the one thing
  that buffer has to do.

If you would rather bind everything yourself, `legu-evil-integration` set to
nil leaves the keymaps alone, and `legu-evil-setup` is callable by hand (it
also suits `evil-collection-setup-hook`). A leader binding for the reading
loop is a `map!` away:

```elisp
(map! :leader :desc "legu queue" "o l" #'legu-list)
```

### What a visual selection means

Evil's selection is not Emacs's region, and legu records line numbers, so
this had to be taught explicitly: `V` on a single line leaves mark and point
equal — `use-region-p` is nil — and `v` ends one character before the last
character it highlighted. `legu-mark` now reads `evil-visual-beginning` and
`evil-visual-end` when evil is in visual state, and `legu-tests.el` pins ten
selections (`V`, `Vj`, `vjj`, `vj$`, `VG`, `viw`, …) to the exact lines they
highlight. Marking then leaves visual state, so the highlight never outlives
the mark it produced.

## Tests

```
emacs -Q --batch -L . -l legu-tests.el -f ert-run-tests-batch-and-exit
```

157 tests. The pure half covers range arithmetic, the sidecar reader, the derived
coverage numbers, the dired column's sums and formatting, painting
precedence and the overlay lifecycle. The other
half drives the real `legu` binary against real scratch git repositories —
including the one test that matters most, that `legu--file-hash` reproduces
the CLI's `:file-hash` byte for byte on files with tabs, CRLF, a non-UTF-8
byte and no trailing newline. If that ever drifts, the fast path is silently
wrong, and this is the test that says so.

The suite skips its integration half when `legu` is not installed, and its
evil group when evil is not on the load path. `-Q` drops the site files that
put a package manager's directories on `load-path`, so name evil and its
`goto-chg` dependency yourself:

```
emacs -Q --batch -L . -L /path/to/evil -L /path/to/goto-chg \
      --eval '(setq evil-want-keybinding nil)' -l evil \
      --eval '(evil-mode 1)' \
      -l legu-tests.el -f ert-run-tests-batch-and-exit
```

evil-collection is not needed. The group gates on evil alone, and the one test
that could tell the two apart checks that legu's queue bindings beat
`compilation-mode`'s, which is base Emacs.

## Known limits

- **A mark is painted before legu confirms it**, in the unverified style.
  Failures revert and are logged to `*legu-failures*`.
- **Ghost regions are shown, never repaired.** A mark that partially overlaps
  an existing record leaves both, which is legu's own semantics. This package
  will not issue a `forget` to tidy them.
- **A corrupt sidecar for the file you are in kills that file's display** —
  tier 0 and the CLI both fail on the same file, and its lines leave the counts
  rather than being called unreviewed. Every other file keeps painting, every
  number stays live, and the queue buffer names the offender from the `errors`
  the CLI reports; `RET` on that line opens it, in `smerge-mode` when it is
  unmerged.
- Paths containing `:` are not `next-error`-navigable in the queue; `RET`
  still works, because text properties are what this package reads.
- No Tramp: `legu-mode` refuses on remote files.
- One buffer shown in a GUI frame and a terminal frame at once is painted in
  the margin for both.

## Not built, on purpose

No prose annotation (`legu ticket` takes a ticket id, and the ticket tracker
owns the rest). No approval or PR workflow. No dashboard tree — dired with
the coverage column is the tree. No inline diff renderer — stock `diff-mode`
in a window. No batch flag/execute state machine.
No client-side region arithmetic: `legu-mark` issues exactly one `legu mark`.
No language-shaped mark command — `C-M-h C-c r r` marks a defun using *your*
Emacs's knowledge of the language, while legu itself stays language-agnostic.
