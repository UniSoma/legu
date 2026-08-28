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
- the `legu` executable on `exec-path`, and `git`

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
| `.` | `legu-describe-region` | who read this, when, at which commit |
| `t` `T` | `legu-note` `legu-visit-ticket` | attach / open a ticket id |
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
| ticket attached | dot, first line only | `*` | — |
| unverified | thin dashes | `:` | none |
| reading frontier | triangle | `>` | — |

A fully unreviewed file looks exactly like a file without the mode, which is the
right visual cost for the buffers you open to grep something.

The mode line shows repo-wide percent reviewed and this buffer's stale count:
` legu 61%▪3`. A trailing `?` means legu cannot currently vouch for what is
drawn; `!` means the store is unreadable; `—` means the file is outside the
eligible set.

## How it stays fast, and honest

Three tiers, with one rule binding them: **local computation may confirm
"read, in place"; it may never pronounce "stale", "moved" or "missing".**
Those verdicts come only from the CLI.

1. **The sidecar and a file hash.** Opening a file reads
   `.review/<path>.edn` and hashes the file — no subprocess at all. A record
   whose stored `file-hash` still matches is exactly the case the CLI's own
   anchoring answers immediately, so it can be painted with no process. A
   record whose hash differs paints *nothing*, and asks for a snapshot.
2. **A repository snapshot**, from one `legu status --json` and one
   `legu stale --json`, run asynchronously and cached. `legu coverage` and
   `legu next` are never invoked: both are arithmetic over the same rows, and
   an ERT test asserts the derived numbers equal the CLI's own, row for row.
   That halves the work a refresh costs.
3. **An optimistic patch** while a mark is in flight, drawn in the unverified
   style until legu confirms it.

A snapshot may only pronounce on a file it is newer than. Without that guard
the union paints a lie: edit inside a region you had read, save, and a
snapshot from a minute ago would still call it read.

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
| `legu-ticket-visit-function` | `knot show` | how `T` opens a ticket |
| `legu-header-line-mode` | off | a one line map of the file |
| `legu-evil-integration` | `t` | bind the queue and diff buffers for evil |
| `legu-evil-source-motions` | `t` | `]r` `[r` `]g` `[g` in source buffers |

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
| `a` | `legu-list-note` | attach a ticket |
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

75 tests. The pure half covers range arithmetic, the EDN reader, the derived
coverage numbers, painting precedence and the overlay lifecycle. The other
half drives the real `legu` binary against real scratch git repositories —
including the one test that matters most, that `legu--file-hash` reproduces
the CLI's `:file-hash` byte for byte on files with tabs, CRLF, a non-UTF-8
byte and no trailing newline. If that ever drifts, the fast path is silently
wrong, and this is the test that says so.

The suite skips its integration half when `legu` is not installed, and its
evil group when evil is not on the load path:

```
emacs -Q --batch -L . -L /path/to/evil -L /path/to/goto-chg \
      -L /path/to/evil-collection \
      --eval '(setq evil-want-keybinding nil)' -l evil -l evil-collection \
      --eval '(progn (evil-mode 1) (evil-collection-init))' \
      -l legu-tests.el -f ert-run-tests-batch-and-exit
```

## Known limits

- **Renames are a blind spot for tier 0.** Sidecars are keyed by the path at
  review time, so a region read under an old name paints as unreviewed until the
  next snapshot lands — seconds, bounded by the `.review/` watcher, not a
  session. `legu-test-integration-rename-is-the-documented-tier0-blind-spot`
  asserts this, so a future fix breaks visibly.
- **A mark is painted before legu confirms it**, in the unverified style.
  Failures revert and are logged to `*legu-failures*`.
- **Ghost regions are shown, never repaired.** A mark that partially overlaps
  an existing record leaves both, which is legu's own semantics. This package
  will not issue a `forget` to tidy them.
- **A corrupt sidecar for the file you are in kills that file's display** —
  tier 0 and the CLI fail on the same file. Every other file keeps painting,
  and the queue buffer names the offender.
- Paths containing `:` are not `next-error`-navigable in the queue; `RET`
  still works, because text properties are what this package reads.
- No Tramp: `legu-mode` refuses on remote files.
- One buffer shown in a GUI frame and a terminal frame at once is painted in
  the margin for both.

## Not built, on purpose

No prose annotation (`legu note` takes a ticket id, and the ticket tracker
owns the rest). No approval or PR workflow. No dashboard tree. No inline diff
renderer — stock `diff-mode` in a window. No batch flag/execute state machine.
No client-side region arithmetic: `legu-mark` issues exactly one `legu mark`.
No language-shaped mark command — `C-M-h C-c r r` marks a defun using *your*
Emacs's knowledge of the language, while legu itself stays language-agnostic.
