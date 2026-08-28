# legu.el — Implementation Specification

Version 1.0 — final. Target Emacs 30.1+, `legu` CLI on `PATH`, GPL-3.0-or-later.

---

## 0. Judge resolutions (every disagreement, the call, the reason)

| # | Disagreement | Call | Reason |
|---|---|---|---|
| 1 | Winning design: daily-use picked D3; implementability and fidelity picked D1 | **D1 is the base**, with D3's frontier guards, unverified-optimistic paint, and `:schema` check grafted in | 2–1, and both D1 judges cite structural correctness (mtime guard, root-scoped write serialization); D3's advantages are graftable, D1's are not |
| 2 | Ghost-diff overlay (D3, daily-use's top pick) vs `*legu-diff*` buffer (D1) | **Buffer only.** No inline diff renderer | Fidelity: §3 forbids a diff UI; the least-owned surface (stock `diff-mode` + two keys) is the defensible minimum. Implementability: "ship the buffer first." The "don't lose your place" win is preserved by displaying it in a bottom side window and restoring the window configuration on `q` |
| 3 | Dired-style `m`/`u`/`x` batch marking (daily-use "mandatory"; fidelity "do not graft") | **No flag/execute state machine.** `legu-list-mark` (`r`) acts on the row at point, or on every row in an active region | Fidelity's non-goal is a hard constraint; region-aware `r` delivers the directory-sweep motion at zero new UI state |
| 4 | Header-line file map always on (D3) vs absent (D1) | **`legu-header-line-mode`, off by default**, rendered from a precomputed buffer-local vector | Daily-use graft #3 (a screen line on every grepped file is the day-30 irritant); implementability's jank objection is answered by forbidding overlay scans in `:eval` |
| 5 | Mode-line percent: this file (D3) vs repo (D1) | **Repo-wide percent + this-buffer stale count** | Daily-use graft #2: the file percent tells you nothing about the 133k-line march |
| 6 | Queue buffer scope | **Repo-wide by default**, file-scoped under `C-u` | Daily-use: file-scoped-by-default is backwards for the post-rebase case |
| 7 | Local fast path: file-hash only (D1) vs file-hash + content-hash (D2/D3) | **`file-hash` only, per record** | Implementability: a local `content-hash` match confirms *state* but not *range* — `try-anchor` checks the hash at the range projected through diff hunks, so painting at the stored range is wrong by the hunk offset. Per-record (not per-sidecar) fixes D1's own all-or-nothing flaw |
| 8 | Ship `legu--content-hash` as a dead drift-detector (implementability #9) | **No.** Not implemented, not tested | Dead code that reimplements the CLI's normalization is the shadow-semantics anti-pattern. `file-hash` is byte-level and cannot drift on a normalization change; the ERT drift test covers it |
| 9 | Write serialization: per file (D2/D3) vs per root (D1) | **Per root, single FIFO** | `purge!` iterates `(stored-paths)` and rewrites *arbitrary* sidecars (legu:511–526); per-file queues are a lost-update race with a 0.3–2.7s window |
| 10 | `legu coverage` invocation | **Never invoked.** Numbers summed from `status --json` rows | Verified: `cmd-coverage` (legu:690+) sums `file-coverage` over `eligible-files`, which is exactly the row set `cmd-status` with no prefix emits. Saves 0.5–2.9s per refresh |
| 11 | `legu next` invocation | **Never invoked.** Queue derived from `status --json` rows | Verified: `cmd-next` derives todo = `1..total` minus reviewed lines, sorted by `(parent, path)`, from the same `file-coverage`. Snapshot is therefore **two** processes, not four |
| 12 | Union re-mark arithmetic (D2 default) | **Killed** | All three judges: a non-atomic `forget`×N + `mark` + `note`×N sequence can permanently destroy committed coverage and provenance to tidy a cosmetic ghost |
| 13 | `legu-mark-defun` as a bound command (D3) | **Killed.** README documents `C-M-h C-c r r` | Fidelity: a language-shaped unit must not become a first-class verb |
| 14 | Ticket creation (`knot add`), Notes dashboard section (D2) | **Killed** | Fidelity §7: legu holds an id and nothing more |
| 15 | magit-section dashboard | **Killed** | Fidelity (scope), implementability (4 deps + undeclared transient≥0.13 upgrade banner) |
| 16 | `repeat-mode` | Not enabled by the package; `(repeat-mode 1)` is in the README's install snippet | Daily-use: don't be pure about it, but don't enable a global mode on the user's behalf |
| 17 | `note` synchronous (D3/D1) | **Asynchronous, on the same per-root write queue** | A synchronous write racing a queued async write reintroduces the lost-update bug rule 9 exists to prevent |

---

## 1. Thesis and scope

`legu.el` is a fringe gutter plus one keystroke. It is the reading analogue of `diff-hl`: a buffer-local minor mode paints which lines of the file you are looking at have been read and which have been read but have since changed, and binds one command meaning *"everything from where I left off down to here, I have now read."* Everything else exists to keep that command at one keystroke and to make it feel instant against a CLI that costs 0.3–2.7s per mark.

The package creates three buffers, requires one dependency that ships inside Emacs 30, and derives its list buffer from `compilation-mode` so `M-g M-n` and `C-x \`` step through review gaps from anywhere in Emacs.

### NON-goals (nothing in this list may be implemented)

1. **Prose annotation.** No command stores text. `legu note` takes a ticket id; there is no `legu-annotate`.
2. **Approval, sign-off, PR, review-request or reviewer-assignment workflow.** The diff buffer supports re-reading. It never grows approve, reject, or comment affordances.
3. **A dashboard.** No tree view, no per-directory rollup, no magit-section buffer.
4. **An inline/ghost diff renderer.** Stock `diff-mode` in a window, nothing bespoke.
5. **Batch flag/execute state machines.** No `m`/`u`/`x` marks, no pending-action list.
6. **Client-side region arithmetic.** No union/split/unmark-on-reselect. `legu-mark` issues exactly one `legu mark`. Ghost regions are shown, never silently repaired.
7. **Ticket creation or ticket state mirroring.** Completion over existing ids; visiting is delegated to a user function.
8. **Reading-order intelligence.** Directory order, exactly as `cmd-next` computes it. No dependency graphs, no churn weighting.
9. **Per-branch state or branch-flavoured UI.**
10. **Sub-region / partial staleness display.**
11. **Per-reviewer colour coding.** Reviewer appears in tooltips and `legu-describe-region` only.
12. **Auto-mark-as-read on dwell.** Not implemented, not customizable.
13. **Writing `.review/*.edn` from Emacs.** The EDN reader is read-only. Every mutation goes through the CLI.
14. **Any shadow cache outside the repo.** Nothing is persisted to `~/.emacs.d`.
15. **A language-shaped mark verb** (`legu-mark-defun` and friends).
16. **Tramp / remote files.** `legu-mode` refuses on `file-remote-p`.
17. **Any timer that spawns a process on a schedule, and any synchronous CLI call in `find-file-hook` or `after-save-hook`.**

---

## 2. File layout and public API

```
legu.el            core: root detection, EDN reader, file hash, process layer,
                   snapshot, legu-mode, all mutating commands, mode line
legu-overlay.el    faces, fringe bitmaps, margin glyphs, painting, teardown,
                   legu-header-line-mode
legu-list.el       *legu* queue buffer (legu-list-mode)
legu-diff.el       *legu-diff: PATH* buffer (legu-diff-mode)
legu-transient.el  legu-dispatch
legu-tests.el      ERT suite (not installed; shipped in-tree)
README.md
```

`legu.el` requires nothing from the others at load; `legu-overlay` is required by `legu.el`, the rest are autoloaded.

**Autoload cookies, exhaustively:** `legu-mode`, `global-legu-mode`, `legu-mark`, `legu-list`, `legu-coverage`, `legu-dispatch`, and the `legu` customization group. Nothing else.

### Public API surface

```elisp
;; Commands (all interactive, §3)
;; Hooks
legu-after-mark-hook            ; run in the source buffer after a successful mark
legu-after-refresh-hook         ; run with the root as sole argument after a snapshot lands
;; Entry points for other packages
(legu-refresh &optional force)  ; safe to call from magit-post-refresh-hook
(legu-root &optional file)      ; the legu root for FILE, or nil
(legu-coverage-plist root)      ; cached (:files N :lines N :reviewed N :stale N :never N) or nil
```

`legu-refresh` is published explicitly so `git`-adjacent packages can invalidate; the README recommends `(add-hook 'magit-post-refresh-hook #'legu-refresh)`.

---

## 3. Modes, commands, keys

### 3.1 Modes

**`legu-mode`** — buffer-local minor mode. Lighter `legu-lighter`. Keymap `legu-mode-map`, which binds exactly one thing: the value of `legu-prefix-key` to `legu-command-map`. Enabling performs no subprocess and no I/O beyond one `insert-file-contents-literally` of the visited file and one `insert-file-contents` of its sidecar.

**`global-legu-mode`** — `define-globalized-minor-mode`, turn-on predicate `legu--turn-on-maybe`. **Opt-in**; the package does not enable it.

```elisp
(defun legu--turn-on-maybe ()
  (when (and buffer-file-name
             (not (file-remote-p buffer-file-name))
             (not (apply #'derived-mode-p legu-exclude-modes))
             (let ((a (file-attributes buffer-file-name)))
               (and a (< (file-attribute-size a) legu-max-file-size)))
             (legu--root-cheap default-directory))
    (legu-mode 1)))
```

`legu--root-cheap` is `(locate-dominating-file DIR ".review")`, memoized in `legu--root-cheap-cache` (a hash keyed by directory, cleared by `legu-refresh` with `force`). **Presence of the store is the opt-in signal**: a repo that has never run `legu` gets nothing, no `git` call, no subprocess, on any visit.

The *authoritative* root, used for every CLI invocation, every sidecar read and every snapshot key, is resolved lazily per buffer into `legu--root` and mirrors `find-root` (legu:768–777) exactly and in order:

```elisp
(defun legu-root (&optional file)
  (let ((default-directory (file-name-directory (or file buffer-file-name default-directory))))
    (or (vc-root-dir)                                        ; git toplevel
        (locate-dominating-file default-directory ".review"))))
```

`project-root` is never used: Emacs 30's `project-try-vc` can return a subdirectory when `project-vc-extra-root-markers` is set.

**`legu-list-mode`** — major mode, derives `compilation-mode`. **`legu-diff-mode`** — major mode, derives `diff-mode`. **`legu-failures-mode`** — major mode, derives `special-mode`. **`legu-header-line-mode`** — buffer-local minor mode, off by default.

### 3.2 Prefix

`legu-prefix-key`, default `"C-c r"`, bound inside `legu-mode-map` only — a buffer-local minor-mode map that exists only in files under a repo with a `.review/` store, i.e. only where the user opted in twice. `C-c r` is unbound in core Emacs and every core `prog-mode` derivative. `C-c C-r` is rejected because it belongs to major modes. `legu-command-map` is also a standalone `defvar` prefix keymap, so `(keymap-global-set "C-c R" legu-command-map)` works without `global-legu-mode`.

### 3.3 `legu-command-map`

| Key | Command | Behaviour |
|---|---|---|
| `r` | `legu-mark` | The one command. §8.2. |
| `SPC` | `legu-set-frontier` | Set the reading frontier to point. |
| `n` | `legu-next-gap` | Next unreviewed-or-stale line in this buffer. Overlay arithmetic, no process. |
| `p` | `legu-previous-gap` | Previous ditto. |
| `]` | `legu-next-stale` | Next stale region in this buffer. |
| `[` | `legu-previous-stale` | Previous ditto. |
| `s` | `legu-diff-stale` | Stale region at point → `*legu-diff*`. `C-u` → `ediff` against the reviewed commit. |
| `.` | `legu-describe-region` | Echo-area provenance line for the region at point. |
| `t` | `legu-note` | Prompt for a ticket id; attach to region at point or active region. |
| `T` | `legu-visit-ticket` | Open the ticket at point via `legu-ticket-visit-function`. |
| `k` | `legu-forget` | Confirms with `yes-or-no-p` naming the range; the message states the record is recoverable from git. |
| `l` | `legu-list` | `*legu*` queue, repo-wide. `C-u` → this file only. |
| `J` | `legu-next-file` | Visit the first queue entry with unread lines; point at its first gap. |
| `c` | `legu-coverage` | Three numbers in the echo area from cache. `C-u` refreshes first. |
| `g` | `legu-refresh` | Repaint from disk + sidecar (free). `C-u` forces an async snapshot refresh. |
| `h` | `legu-toggle-highlights` | Buffer-local hide/show. `C-u` toggles for every legu buffer. |
| `f` | `legu-list-failures` | `*legu-failures*`. |
| `?` | `legu-dispatch` | Transient. |

Sixteen commands plus the menu. Nothing else is bound anywhere in a source buffer.

### 3.4 Repeat map

```elisp
(defvar-keymap legu-repeat-map
  :repeat t
  "r" #'legu-mark   "n" #'legu-next-gap   "p" #'legu-previous-gap
  "]" #'legu-next-stale "[" #'legu-previous-stale
  "s" #'legu-diff-stale "." #'legu-describe-region
  "SPC" #'legu-set-frontier)
```

Out of the box the loop is `C-c r r` / `C-c r n`. The README's install snippet is:

```elisp
(global-legu-mode 1)
(repeat-mode 1)   ;; makes the reading loop  C-c r r  then  n r n r
```

### 3.5 `defcustom` — complete list

```elisp
(defgroup legu nil "Review coverage." :group 'tools :prefix "legu-")

legu-executable          string   "legu"
legu-prefix-key          key      "C-c r"          ; setter rebuilds legu-mode-map
legu-save-before-mark    choice   t | 'ask | nil   ; default t
legu-indicator-style     choice   'fringe | 'margin | 'face-only   ; default 'fringe
legu-indicator-side      choice   'left | 'right   ; default 'left
legu-ascii-glyphs        boolean  nil              ; force ASCII margin glyphs
legu-margin-glyphs       alist    ((reviewed . "│") (stale . "!") (note . "*")
                                   (unverified . ":") (frontier . ">"))
legu-margin-ascii-glyphs alist    ((reviewed . "|") (stale . "!") (note . "*")
                                   (unverified . ":") (frontier . ">"))
legu-frontier-max        integer  400   ; confirm a frontier mark larger than this
legu-large-region-lines  integer  200   ; once-per-session guidance nudge
legu-snapshot-initial-delay number 2.0  ; idle seconds before the first snapshot in a root
legu-snapshot-debounce   number   5.0   ; seconds after a write settles
legu-store-debounce      number   2.0   ; seconds after a .review/ file-notify event
legu-slow-root-threshold number   1.5   ; a root whose last refresh exceeded this
legu-slow-root-debounce  number   15.0  ; uses this debounce instead
legu-watch-store         boolean  t     ; file-notify on .review/
legu-exclude-modes       list     '(image-mode doc-view-mode archive-mode tar-mode
                                    hexl-mode special-mode)
legu-max-file-size       integer  2000000
legu-next-limit          integer  50    ; queue rows
legu-list-filter         choice   'all | 'stale | 'unread   ; default 'all
legu-ticket-completion-function function  #'legu-known-tickets
legu-ticket-visit-function      function  #'legu-visit-ticket-default
legu-header-line-slices  integer  0     ; 0 = fit the window width
```

`legu-visit-ticket-default` runs `knot show ID` in a `compilation` buffer when `knot` is on `exec-path`, else `user-error`s naming the defcustom. `legu-known-tickets` returns every ticket id in the root's snapshot notes.

### 3.6 `defface` — complete list

```elisp
legu-reviewed        ; fringe/margin bar for read-and-current. Default:
                     ;   ((((background light)) :foreground "#6a8f6a")
                     ;    (((background dark))  :foreground "#5f7f5f"))
legu-stale           ; :inherit warning
legu-stale-region    ; the ONLY background. light: (:background "#fdf3e3" :extend t)
                     ;                       dark:  (:background "#332b1c" :extend t)
legu-note            ; :inherit font-lock-constant-face
legu-unverified      ; :inherit shadow
legu-frontier        ; :inherit font-lock-keyword-face
legu-ignored         ; :inherit shadow  (out-of-scope file marker)
legu-missing         ; :inherit error   (state "missing" rows in the queue)
legu-list-heading    ; :inherit magit-section-heading-like: bold, :inherit font-lock-doc-face
legu-list-count      ; :inherit font-lock-comment-face
legu-error           ; :inherit error   (broken-store lighter and banner)
```

---

## 4. Data layer

### 4.1 Exact CLI invocations

The package issues **five** distinct invocations. Nothing else.

| Purpose | argv (after `legu-executable`) | Sync? | Frequency |
|---|---|---|---|
| capability probe | `("--help")` | async, once per session per executable | once |
| snapshot A | `("status" "--json")` | async | §4.5 triggers |
| snapshot B | `("stale" "--json")` | async, concurrent with A | §4.5 triggers |
| mark | `("mark" "PATH:START-END")` or `("mark" "PATH")` | async, root FIFO | per user action |
| note | `("note" "PATH:START-END" "TICKET")` | async, root FIFO | per user action |
| forget | `("forget" "PATH:START-END")` | async, root FIFO | per user action |

`--reviewer` is appended to `mark` when the transient's sticky `--reviewer=` infix is set.

**`legu coverage` and `legu next` are never invoked.** Both are derived (§4.3). This is verified against source: `cmd-coverage` (legu:690+) sums `file-coverage` over `eligible-files`, the same row set `cmd-status` with no prefix emits; `cmd-next` (legu:665+) derives todo lines as `1..total` minus reviewed lines over the same rows. Removing them takes a snapshot from four repo scans to two.

**`status` is always invoked with no path argument.** `cmd-status` (legu:614–620) computes `resolved-by-path` and `eligible-files` *before* filtering by prefix, so `status <path>` costs the same as `status` (measured 585ms vs 592ms clean, ~2.9s each dirty). A path argument buys nothing and loses the repo picture.

### 4.2 Exact JSON consumed

```jsonc
// status --json
{"files":[{"path":"src/a.clj","total":169,"reviewed":40,"stale":7,
           "unreviewed":122,"ranges":"40-95,120"}],
 "notes":[{"path":"src/a.clj","start":112,"end":130,"ticket":"lgu-01k7","state":"reviewed"}]}

// stale --json
{"stale":[{"path":"src/a.clj","start":45,"end":50,
           "reason":"content changed","state":"stale"}]}
```

Consumed keys only; **unknown keys are ignored, never validated**. Known shape hazards, all handled:

- `"ranges"` is a formatted display string. Empty is the literal `"-"`, not `""`.
- `notes[]` entries for an opaque (binary/empty) record have **no** `start`/`end` keys.
- `stale[]` entries mix `start:null` (truncated text file) and *absent* `start` (opaque record) in the same array. Both must read as nil, hence `:null-object nil`.
- `stale[]` mixes `state:"stale"` and `state:"missing"`. Filter on `state`.
- Overlapping records produce overlapping `stale[]` entries. Union before painting.
- `{"files":[],"notes":[]}` with exit 0 is the **do-not-paint** signal (path nonexistent, untracked, or `.reviewignore`d), not an empty repo.

**Exactly one function parses `ranges`:**

```elisp
(defun legu--parse-ranges (s)
  "Parse legu's formatted range string into a list of (START . END).
S is display output: comma-joined \"a-b\" spans and bare \"a\" lines, with
the literal string \"-\" for the empty set.  The day legu emits structured
pairs, this is the only call site to change."
  (unless (or (null s) (equal s "-") (equal s ""))
    (mapcar (lambda (c)
              (if (string-match "\\`\\([0-9]+\\)-\\([0-9]+\\)\\'" c)
                  (cons (string-to-number (match-string 1 c))
                        (string-to-number (match-string 2 c)))
                (let ((n (string-to-number c))) (cons n n))))
            (split-string s "," t))))
```

### 4.3 Derived values

```elisp
;; coverage, exactly cmd-coverage's arithmetic over the status rows
(:files    (length rows)
 :lines    (Σ total)
 :reviewed (Σ reviewed)
 :stale    (Σ stale)
 :never    (- lines reviewed stale))

;; queue, exactly cmd-next's
(defun legu--queue (rows limit)
  (let ((gaps (seq-filter (lambda (r) (> (+ (alist-get 'unreviewed r)
                                            (alist-get 'stale r)) 0))
                          rows)))
    (seq-take
     (sort gaps
           (lambda (a b)
             (let ((da (legu--parent-key (alist-get 'path a)))
                   (db (legu--parent-key (alist-get 'path b))))
               (if (equal da db)
                   (string< (alist-get 'path a) (alist-get 'path b))
                 (string< da db)))))
     limit)))

(defun legu--parent-key (p)
  "Reproduce (str (fs/parent (fs/path P))): no trailing slash, \"\" at top level."
  (let ((d (file-name-directory p))) (if d (directory-file-name d) "")))
```

The trailing-slash strip is not cosmetic: `"src"` vs `"src-x"` orders differently from `"src/"` vs `"src-x/"`.

Each queue row's todo ranges are the complement of that row's reviewed ranges within `1..total`.

### 4.4 The three-tier truth model

**The rule that binds them: local computation may confirm "reviewed, in place". It may never pronounce "stale", "moved", or "missing". Those verdicts come only from the CLI.**

**Tier 0 — sidecar + file hash. Instant, zero subprocesses.**

On `legu-mode` enable, `after-revert-hook`, `after-save-hook`, and `legu-refresh`:

1. Read `.review/<relpath>.edn` with `insert-file-contents`; parse with `legu--read-edn` (§4.6). Parse failure or `:schema` ≠ 1 ⇒ tier 0 yields nothing for this file.
2. Compute the file hash in process:

```elisp
(defun legu--file-hash (file)
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert-file-contents-literally file)
    (secure-hash 'sha256 (current-buffer))))
```

This reproduces legu's `:file-hash` byte-for-byte: `sha256-bytes` (legu:114) hashes `fs/read-all-bytes` of the worktree file.

3. **Per record**, not per sidecar: a record whose `:file-hash` equals the file hash is *reviewed at its stored `:start`–`:end`*, because `try-anchor`'s first branch (legu:270–272) returns exactly that with no projection. Paint it. Records whose `:file-hash` differs yield **nothing** — not stale, not reviewed — and mark the buffer as having unresolved records.
4. `:notes` records are resolved the same way for the note glyph.

`legu--content-hash` is **not implemented**. A local content-hash match confirms the region's *state* but not its *range*: `try-anchor` checks the hash at the range projected through `-U0` diff hunks (legu:274–281), so painting at the stored range is wrong by the hunk offset whenever anything was inserted above.

**Tier 1 — the repo-wide snapshot. Async, cached, rare.** §4.5.

**Tier 2 — optimistic local patch.** On a successful `mark`, the range is spliced into the snapshot's reviewed set for that path and subtracted from its stale set; `forget` and `note` do the equivalent. The generation counter is *not* bumped; the next real snapshot replaces the patch wholesale.

**Painting precedence, per path P:**

```
reviewed(P) = tier0-verified(P) ∪ trusted-snapshot-reviewed(P)
stale(P)    = trusted-snapshot-stale(P) minus reviewed(P)
unreviewed  = 1..total minus both
```

**`trusted-snapshot-*(P)` is nil unless `(:started snapshot)` is strictly later than P's current file mtime.** Without this guard the union paints a lie: you edit inside a reviewed region and save, tier 0 now says nothing, and a snapshot taken 90 seconds ago still says reviewed. The mtime comparison also covers `git pull`, `git checkout`, and edits made outside Emacs.

When the snapshot is untrusted for P *and* tier 0 has unresolved records, the buffer paints those records in the **unverified** style, the lighter shows `?` after the percent, and a snapshot refresh is requested.

**Known incompleteness, stated in the README:** sidecars are keyed by the path at review time. A region read in `old.clj` that git later renamed into the file you are looking at lives in `.review/old.clj.edn`, and tier 0 misses it. The file under-reports until the next snapshot lands (bounded by the `.review/` watcher and the post-write debounce — seconds, not a session).

### 4.5 The snapshot: cache and invalidation

One entry per root in `legu--snapshots` (hash keyed by absolute root):

```elisp
(:generation  N
 :started     TIME              ; when the processes were launched
 :duration    SECONDS           ; wall time of the last completed refresh
 :rows        HASH path -> (:total N :reviewed N :stale N :unreviewed N
                            :ranges ((a . b) ...))
 :eligible    HASH path -> t    ; the set of eligible paths (for out-of-scope detection)
 :stale       HASH path -> ((START END REASON STATE) ...)
 :notes       HASH path -> ((START END TICKET STATE) ...)
 :coverage    (:files N :lines N :reviewed N :stale N :never N)
 :queue       ((path unreviewed stale ranges) ...)
 :state       fresh | refreshing | error
 :error       nil | (:kind broken-store :file ABSPATH :message STRING)
 :error-mtime nil | TIME)       ; mtime of the offending sidecar when it broke
```

Refresh triggers, exhaustively — **there is no timer that polls and no hook that shells out:**

| Trigger | Delay |
|---|---|
| First `legu-mode` activation in a root this session | `legu-snapshot-initial-delay` idle |
| `legu-refresh` with `force` (`C-u C-c r g`), `C-u legu-coverage`, `legu-list` revert (`g`) | immediate |
| Completion of any `mark`/`note`/`forget` **and** the root's write FIFO draining empty | `legu-snapshot-debounce`, coalescing |
| `file-notify` on `<root>/.review/` (recursive), when `legu-watch-store` | `legu-store-debounce`, coalescing |
| `legu-refresh` called by a third party (`magit-post-refresh-hook`) | `legu-snapshot-debounce` |

If `(:duration snapshot)` exceeds `legu-slow-root-threshold`, the post-write and store debounces become `legu-slow-root-debounce`, and the queue header appends `· auto-refresh throttled (last 2.9s)`.

A refresh **never starts while the root's write FIFO is non-empty**; it is rescheduled on drain.

Serving is stale-while-revalidate: readers get the current snapshot immediately, however old, plus its age. Nothing ever blocks on a refresh.

The `.review/` watcher is registered on the first `legu-mode` activation in a root and removed when the last `legu-mode` buffer in that root is killed. If `file-notify` is unavailable the feature degrades silently to `g`.

### 4.6 The EDN reader

`legu--read-edn` is a ~70-line recursive-descent reader over exactly what `save-state!` pprints: maps, vectors, keywords, strings with `\"`/`\\` escapes, integers, `true`, `false`, `nil`. It returns an alist keyed by symbols (`:file-hash` → `file-hash`). It is strictly read-only and **never signals**: anything unrecognized returns nil, which downgrades tier 0 for that path.

`legu--sidecar-records` checks `(alist-get 'schema data)` and returns nil unless it is `1`. legu has no `--version` (verified: `legu --version` exits 1, "unknown option"), so `:schema` is the only version handshake available.

### 4.7 Async protocol

Every invocation, without exception:

```elisp
(defun legu--run (root args callback)
  "Run legu with ARGS in ROOT.  CALLBACK is (STATUS STDOUT-STRING STDERR-STRING),
STATUS one of `ok', `failed', `broken-store'."
  (let* ((program (or (executable-find legu-executable)
                      (user-error "legu: executable %S not found on exec-path"
                                  legu-executable)))
         (default-directory root)
         (out (generate-new-buffer " *legu-out*"))
         (err (generate-new-buffer " *legu-err*")))
    (make-process
     :name "legu" :buffer out :noquery t :connection-type 'pipe
     :stderr (make-pipe-process :name "legu-err" :buffer err
                                :noquery t :sentinel #'ignore)
     :command (cons program args)
     :sentinel (lambda (p _e) ...))))
```

Non-negotiable details, each verified:

- **`make-process`, never `call-process`.** Nothing in this package blocks Emacs except the `git diff` in §7.2 (2ms).
- **`:command` resolves on `exec-path`, not `default-directory`.** `executable-find` is mandatory.
- **`default-directory` is bound to the root**, because `find-root` walks up from the working directory.
- **Arguments are a list.** Never `shell-command`: `PATH:START-END` is one positional token, and paths containing spaces, quotes, and even a literal `:12-14` suffix round-trip correctly through argv (verified).
- **Paths passed are repo-relative** (`file-relative-name`); paths returned are repo-relative and resolved against the root.
- **stderr goes to a separate `make-pipe-process` with `:sentinel #'ignore`.** `legu mark` on an untracked or `.reviewignore`d file writes a warning to stderr *and* valid JSON to stdout *and* exits 0; merged, the warning destroys the parse. The `ignore` sentinel is required or Emacs writes `"Process … finished"` into the stderr buffer.
- **Exit code is the only failure signal.** Non-empty stderr with exit 0 is a warning, surfaced once with `message`.
- Success requires **both** `(eq (process-status p) 'exit)` and `(= 0 (process-exit-status p))`; a killed process still delivers a sentinel with `status=signal exit-status=9`.
- **JSON:** `(json-parse-buffer :object-type 'alist :array-type 'list :null-object nil :false-object nil)`, wrapped in `condition-case` catching `json-parse-error` and `json-utf8-decode-error`. The null/false defaults are not optional — `:null` and `:false` are truthy.
- **Generation counter per root**, compared in the sentinel; superseded results are discarded. Buffer painting additionally compares a buffer-local `legu--gen`.
- **`kill-buffer-hook`** kills in-flight processes owned by the buffer and cancels its timers; stdout/stderr buffers are killed in an `unwind-protect`.
- **Writes are serialized per root** in `legu--write-queue` (hash root → list of pending jobs), at most one in flight. `purge!` (legu:511–526) iterates `(stored-paths)` and `save-state!`s any sidecar it prunes, so two concurrent marks in *different* files can both rewrite a third sidecar. Per-file queues are a lost-update race. When the queue is deeper than one, the echo area shows `legu: 3 writes pending`.

### 4.8 Error handling — every failure mode

| Condition | Detection | Response |
|---|---|---|
| `legu` not on `exec-path` | `executable-find` nil | `user-error` naming `legu-executable`. `legu-mode` stays on and paints from tier 0 (which needs no binary). |
| Probe `legu --help` non-zero | exit ≠ 0 | Root enters `error` state; banner in queue buffer; writes blocked. |
| exit 0, `{"files":[],"notes":[]}` | empty `files` | **Do not paint.** If the buffer's path is absent from `(:eligible snapshot)`, render it out-of-scope: lighter ` legu —`, one `legu-ignored` glyph on line 1, no other decoration. Answers "why is this file always unread" on screen. |
| exit 0, non-empty stderr (`is not tracked by git`, `is excluded by .reviewignore`, `.reviewignore needs git to match`) | stderr non-empty, exit 0 | The operation stands. `message` the stderr line once per path per session. |
| `legu: no such file: P` (exit 1) | exit 1 | Optimistic overlay reverts, frontier reverts, row appended to `*legu-failures*`, `message` in `warning` face. |
| `legu: range A-B outside P (1-N)` (exit 1) | exit 1 | Same. This is the friendly unsaved-buffer failure. |
| `legu: path is outside the repository: P` | exit 1 | Same. |
| `legu: unknown command/option` | exit 1 | Root enters `error` state (the CLI is not the version we speak) and the banner says so. |
| `legu: cannot read <ABS>: not a review record` / `bad line range in …` (exit 1, empty stdout) | stderr matches `\`legu: cannot read \\(.*\\): \\(.*\\)$` | **Broken store.** §4.9. |
| Malformed JSON on stdout | `json-parse-error` | Root enters `error` state with the raw first 200 bytes in the banner. Previous snapshot is retained. |
| Invalid UTF-8 on stdout | `json-utf8-decode-error` | Same, message "legu emitted invalid UTF-8". |
| Process killed (buffer closed, superseded) | `status=signal` | Silent; generation check discards. |
| Sidecar unparseable by `legu--read-edn` | reader returns nil | Tier 0 off for that file only; buffer paints from the snapshot alone. |
| Sidecar `:schema` ≠ 1 | schema check | Tier 0 off **for the whole root**; `message` once: "legu: sidecar schema N is newer than this package; painting from the CLI only". |
| `first-change-hook` fires | buffer modified | §6.4. |
| `mark`/`note`/`forget` while root is `error` | state check | Refused with the store error message; no process spawned. |

### 4.9 Broken store

`.review/*.edn` is committed, so merge conflicts are expected, and `load-state` (legu:167–180) calls `die` on any malformed record — so *every* command exits 1 with empty stdout. Naively wired, the package would appear dead.

On detecting the `cannot read` stderr shape:

1. Root `:state` ← `error`, `:error` ← `(:kind broken-store :file ABSPATH :message MSG)`, `:error-mtime` ← the file's current mtime.
2. The previous snapshot's data is **retained** and served, greyed, with the age in the header.
3. Lighter becomes ` legu!` in `legu-error`. One `message` fires, not repeated.
4. Writes are blocked for the root.
5. Further snapshot attempts are suppressed until the offending file's mtime changes or the user forces `C-u C-c r g`.
6. `legu-visit-broken-store` (in the transient and as a button in the queue banner) opens the file; if conflict markers are present it enables `smerge-mode`.
7. **Tier 0 keeps painting every file whose own sidecar parses.** A conflict in `src/core.clj.edn` leaves the other 696 files fully readable. If the conflicted sidecar *is* the current buffer's, tier 0 fails on the same file the CLI does; the package names it rather than routing around it.

---

## 5. Required changes to the legu CLI

Three, ranked. The package ships and works without all of them; each one deletes elisp or removes a failure mode.

### CLI-1 — scope `purge!` in `mark` (performance; blocks nothing, but is the whole reason optimistic UI is load-bearing)

`cmd-mark` calls `purge!` with `(constantly true)`, which runs `resolve-region` — a `git show` plus a `git diff --no-index` in a fresh temp dir — over **every** stored record in the repo (legu:511–526). Measured: `mark` costs 319ms clean and **2750ms** on a dirty 700-file repo. `cmd-note` is 0.10s because its `extra-pred` filters on the ticket id *before* `superseded?` resolves anything.

Requirement: `purge!` must only resolve records that can possibly be superseded — those in the target file's own sidecar, plus sidecars git reports as renames of it (`git log --follow --name-only`, or the existing `candidate-paths` machinery run in reverse). Equivalently, accept a new flag:

```
legu mark <target> --no-supersede    # skip purge! entirely
```

No JSON change. Effect: 2.7s → ~0.1s on the most frequent verb in the tool.

### CLI-2 — `legu --version`

Today `legu --version` exits 1 with `unknown option: --version`. There is no version handshake at all; the elisp is reduced to probing `--help` and reading `:schema` out of a sidecar.

```
$ legu --version --json
{"version":"0.4.1","schema":1}
$ legu --version
legu 0.4.1 (store schema 1)
```

`"schema"` is the sidecar schema the binary writes. Exit 0.

### CLI-3 — survive one corrupt sidecar

A single merge-conflicted `.review/*.edn` makes `status`, `stale`, `coverage`, `next`, `mark`, `note` and `forget` all exit 1 with empty stdout. One conflict costs the entire tool.

Requirement: `load-state` must not `die`. Read commands skip the unreadable sidecar, continue, exit 0, and report it as data; write commands still `die` when the *target* sidecar is the broken one.

Every read command's `--json` object gains one optional key:

```jsonc
{"files":[...], "notes":[...],
 "errors":[{"file":".review/src/core.clj.edn",
            "reason":"not a review record"}]}
```

`"errors"` is repo-root-relative (unlike today's absolute path in stderr), omitted when empty, and mirrored to stderr in the human renderer as today. The elisp renders `errors[]` in the queue banner and keeps every other number.

**Explicitly not requested**, to keep this list minimal: structured range pairs (one parser function absorbs the string), per-file stale ranges (the repo-wide `stale` is already the only call), region ids, and `commit`/`reviewer`/`timestamp` in `status --json` (the EDN reader is needed for tier 0 regardless, so it is free to read them there).

---

## 6. In-buffer rendering

### 6.1 States and channels

Two channels: **gutter glyph = review state**, **background = alarm only**. Reviewed code is the eventual normal state of a well-read file; tinting it means tinting almost everything and fighting font-lock for hours.

| State | GUI fringe | TTY / margin | Background |
|---|---|---|---|
| unreviewed | nothing | nothing | none |
| reviewed | `legu-bmp-bar` — 2px solid, periodic, face `legu-reviewed` | `│` / `\|` | none |
| stale | `legu-bmp-stale` — 3px dashed, periodic, face `legu-stale` | `!` | `legu-stale-region`, `:extend t` |
| noted | `legu-bmp-note` — filled dot, **first line of the note only**, replaces the bar there, face `legu-note` | `*` | unchanged |
| unverified | `legu-bmp-dashed` — 1px dashed, face `legu-unverified` | `:` | none (any stale tint removed) |
| frontier | `legu-bmp-frontier` — right triangle, one line, face `legu-frontier` | `>` | none |
| out of scope | `legu-bmp-dashed`, line 1 only, face `legu-ignored` | `~` | none |

Absence is the signal for unreviewed: a fully unread file looks exactly like a file without `legu-mode`, which is the correct visual cost for the 90% of buffers you open to grep something.

### 6.2 Terminal fallback

`legu-indicator-style` defaults to `fringe`. The **effective** style is computed per displayed window, never cached at mode-enable, because one buffer can be shown in a GUI frame and an `emacsclient -nw` frame simultaneously: when `(display-graphic-p (window-frame w))` is nil, that window falls back to `margin`. A `(left-fringe …)` display spec on a TTY renders nothing and fails silently, which is worse than an error.

Glyphs are chosen from `legu-margin-glyphs`, falling back to `legu-margin-ascii-glyphs` when `legu-ascii-glyphs` is non-nil or `(char-displayable-p ...)` is nil.

Margins are installed the only way that sticks — a bare `set-window-margins` is reverted by the next `set-window-buffer`:

```elisp
(setq-local left-margin-width 1)   ; or right-margin-width
(dolist (win (get-buffer-window-list nil nil t))
  (set-window-buffer win (current-buffer)))
```

re-applied from `window-buffer-change-functions` (not `window-configuration-change-hook`, which fires on every split and resize).

`face-only` drops glyphs and paints reviewed lines with a 3% background, for users whose fringe already belongs to `diff-hl`.

### 6.3 Overlay mechanics

Overlays, never text properties: text properties travel with `kill-region`/`yank`, so cutting a reviewed block and pasting it elsewhere would mint a reviewed mark legu never issued (verified).

Per contiguous same-state range: one region overlay from `(line-beginning-position START)` to `(line-beginning-position (1+ END))`, plus one zero-length overlay per line carrying the glyph as `before-string`. Every overlay gets:

```elisp
'legu t              ; single teardown handle
'legu-state SYM      ; reviewed | stale | note | unverified | frontier | ignored
'evaporate t         ; deleting the text under one must not leave a live zombie
'priority N          ; reviewed 10, stale 20, note 30 — low, so region, isearch,
                     ; hl-line and flymake all win
```

`rear-advance` is **nil**: typing at the start of the first unreviewed line after a reviewed region must not extend the reviewed region.

Teardown walks the buffer-local `legu--overlays` list and `delete-overlay`s each, then a whole-buffer `(remove-overlays (point-min) (point-max) 'legu t)` as belt and braces. A *partial-span* `remove-overlays` is never used: it splits partially-overlapping overlays into zombie fragments (verified).

No windowing, batching or coalescing beyond per-range. Emacs 29.1 replaced the overlay implementation with an interval tree; 10 000 overlays cost 4ms to create and 0.1ms for 200 mid-buffer edits.

### 6.4 Unsaved-buffer policy

legu measures the file on disk. `legu mark` on a modified buffer hashes disk content the user never read, and — verified — **silently succeeds with the wrong content** whenever the buffer is no shorter than the file.

- **`first-change-hook`** (buffer-local; fires once per modified-flag transition, not per keystroke): re-face every legu overlay to `legu-unverified`, swap glyphs to the dashed/`:` variant, remove the stale tint, set `legu--unverified`, dim the header line. **No process is spawned and no repaint from the snapshot occurs** — every legu answer describes a file that is no longer on screen. The overlays are *not* deleted; the user still wants to see roughly where they had read, and Emacs adjusts their positions across every edit in C for free.
- **`after-change-functions` is not used at all.** The only thing it could contribute — moving overlays — Emacs already does.
- **`after-save-hook`**: clear `legu--unverified`, re-run tier 0, repaint, and request a debounced snapshot refresh if any record is unresolved.
- **`after-revert-hook`**: full teardown, then tier 0.
- **`legu-mark`, `legu-note`, `legu-forget`** all pass through `legu--ensure-saved` first, driven by `legu-save-before-mark`: `t` saves silently (the default — the alternative is hashing bytes the user never saw), `ask` prompts with `y-or-n-p`, `nil` refuses with

  ```
  legu: refusing to act on a modified buffer (legu reads the file on disk)
  ```

  There is no setting that acts on a modified buffer silently.

### 6.5 The reading frontier

Buffer-local marker, insertion type `t`, **never persisted** — re-derived from the painted state on every open, which is both correct and free.

- On `legu-mode` enable, after the tier-0 paint: frontier = the first line of the first gap at or after `point-min`. If the file is fully reviewed, frontier = last line and the glyph is not drawn.
- After a successful mark: frontier = the line after the marked region's end, clamped to `point-max`.
- After a failed mark: frontier reverts.
- `C-c r SPC` sets it to point unconditionally.

### 6.6 Mode line

```elisp
(defvar legu-lighter '(:eval (legu--lighter)))
(put 'legu-lighter 'risky-local-variable t)   ; without this the lighter renders
                                              ; NOTHING AT ALL, silently
```

| Display | Meaning |
|---|---|
| ` legu 61%▪3` | 61% of eligible lines read **repo-wide**; 3 stale regions **in this buffer**. `▪3` in `warning` face, omitted when zero. |
| ` legu 61%?` | snapshot untrusted for this path, or tier 0 has unresolved records |
| ` legu?` | buffer modified; indicators dimmed, mutations refused |
| ` legu!` | store is broken (`legu-error` face) |
| ` legu —` | file is out of scope (`.reviewignore`d or untracked) |

`legu--lighter` reads precomputed buffer-locals (`legu--counts`, `legu--unverified`, `legu--scope`) and calls `format`. It **never** scans overlays and never touches the filesystem: `:eval` runs on every redisplay, and `overlays-in` over a buffer costs 45µs there — visible scroll jank.

### 6.7 `legu-header-line-mode` (off by default)

A one-line proportional map of *this file*. One character per equal slice, `legu-header-line-slices` or the window width; a slice takes its most urgent line's state (stale > unreviewed > reviewed); the slice containing point is reverse-video. Clicking a slice jumps there.

**It is rendered from a precomputed buffer-local string**, `legu--header-string`, recomputed only in `legu--paint` and in `window-size-change-functions`. `header-line-format` is `'(:eval legu--header-string)` — a variable read, never a scan. Computing slice states inside `:eval` would be the exact 45µs-per-redisplay jank §6.6 forbids.

---

## 7. UI buffers

### 7.1 `*legu*` — the queue (`legu-list-mode`, derives `compilation-mode`)

One per root; named `*legu: aishell*` when more than one root is live. Repo-wide by default; `C-u legu-list` scopes to the current file. Built entirely from the cached snapshot — `g` re-shells, nothing else does.

```
Review coverage — aishell                          snapshot 40s ago
  never read   118902  89.3%  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
  read         12118    9.1%  ███
  stale         2061    1.5%  ▌
  eligible     697 files / 133081 lines                    [f] all

STALE  9 regions
src/aishell/core.clj:40:95:    stale    content changed     read 2026-07-02  lgu-01k7
src/aishell/core.clj:210:244:  stale    content changed     read 2026-07-02
src/aishell/db/pool.clj:1:88:  stale    block moved         read 2026-06-19
docs/CONFIGURATION.md:900:912: stale    content changed     read 2026-08-01
resources/schema.sql:1:1:      missing  file is gone        read 2026-05-30

NEXT  20 files
src/aishell/api/handlers.clj:1:412:  412 unread    0 stale
src/aishell/api/routes.clj:1:96:      96 unread    0 stale
src/aishell/core.clj:96:209:         114 unread   65 stale   1-39,96-209,245-380
src/aishell/db/migrate.clj:1:203:    203 unread    0 stale

RET visit   r mark   s diff   t ticket   k forget   f filter   g refresh   c coverage
```

The three coverage numbers are three labelled rows with proportional bars, permanently visible — this is where §8 of the requirements is satisfied, not in an echo-area line you must ask for.

**`next-error` integration.** `compilation-error-regexp-alist` is set buffer-locally to one entry:

```elisp
'(("^\\([^ \t\n:][^\n:]*\\):\\([0-9]+\\):\\([0-9]+\\):" 1 2 nil 2))
```

so `M-g M-n` and `C-x \`` step through review gaps from any buffer in Emacs. The `path:start:end:` prefix on every content row exists for this. **The regexp is a bridge, not the source of truth**: each row also carries `legu-path`, `legu-start`, `legu-end`, `legu-kind` text properties, and `legu-list-visit` uses those. A path containing `:` (legal, verified) renders and visits correctly but is not `next-error`-navigable; that is a documented limit.

`revert-buffer-function` is `legu--list-revert` (replacing `recompile`): it forces a snapshot refresh and re-renders on completion, restoring point by line content.

| Key | Command |
|---|---|
| `n` / `p` / `M-n` / `M-p` / `TAB` / `q` | inherited from `compilation-mode` |
| `RET` | `legu-list-visit` — visit the path at its range start |
| `o` | `legu-list-visit-other-window` |
| `r` | `legu-list-mark` — mark the row at point; **region-aware**: with an active region, marks every row it touches, enqueued in order on the root FIFO, one confirmation naming the count |
| `s` | `legu-list-diff` — diff the stale region at point |
| `t` | `legu-list-note` |
| `k` | `legu-list-forget` |
| `f` | `legu-list-toggle-filter` — cycles `all` → `stale` → `unread` |
| `g` | `revert-buffer` |
| `c` | `legu-coverage` |
| `?` | `legu-dispatch` |

Broken-store banner, rendered above the coverage block and suppressing nothing else:

```
STORE ERROR — every legu command is failing
  .review/src/aishell/core.clj.edn   not a review record
  RET visits the file (smerge-mode if it has conflict markers), then press g.
  Numbers below are from the last good snapshot, 6m ago.
```

### 7.2 `*legu-diff: <path>*` (`legu-diff-mode`, derives `diff-mode`)

`git diff <reviewed-commit> -- <path>`, run **synchronously** (measured 2ms), point moved to the first hunk intersecting the region's current range. The reviewed commit comes from the sidecar via `legu--read-edn`; no `--json` shape emits it.

Displayed in a bottom side window via `display-buffer-in-side-window` (`(side . bottom) (window-height . 0.4)`); the prior window configuration is saved and restored by `q`, so you do not lose your place in the source — the interaction win the inline renderer was going to buy, without owning a renderer.

```
─────────────────────────────────────────────────────────────────────────
 stale  src/aishell/core.clj:40-95   read 2026-07-14 by jonas at a1b2c3d
 content changed          [r] re-mark and close   [e] ediff   [q] quit
─────────────────────────────────────────────────────────────────────────
diff --git a/src/aishell/core.clj b/src/aishell/core.clj
--- a/src/aishell/core.clj
+++ b/src/aishell/core.clj
@@ -51,7 +51,9 @@ (defn dispatch
-  (let [handler (get routes path)]
-    (handler req))
+  (let [handler (or (get routes path) default-handler)]
+    (when-not handler (throw (ex-info "no route" {:path path})))
+    (handler req))
```

The two header lines are `header-line-format`, not buffer text, so `diff-mode`'s parsing is untouched.

| Key | Command |
|---|---|
| everything | inherited from `diff-mode` (`C-c C-c` visits source, hunk navigation) |
| `r` | `legu-diff-remark` — mark the region at its current range, restore the window configuration |
| `e` | `legu-diff-ediff` — `ediff-revision` against the reviewed commit |
| `q` | `legu-diff-quit` — restore the window configuration |

### 7.3 `*legu-failures*` (`legu-failures-mode`, derives `special-mode`)

Written only when a mutation's process exits non-zero. Without it an async miss is a silently lost mark.

```
Failed legu writes (2)

  17:04:12  mark src/aishell/core.clj:40-95
            legu: range 40-95 outside src/aishell/core.clj (1-88)
            [r] retry   [RET] visit   [k] discard

  17:09:55  note ops/deploy.yaml:12-30 lgu-01m2
            legu: cannot read /home/j/aishell/.review/ops/deploy.yaml.edn: not a review record
            [r] retry   [RET] visit sidecar   [k] discard
```

Keys: `r` `legu-failures-retry`, `RET` `legu-failures-visit`, `k` `legu-failures-discard`, `K` `legu-failures-discard-all`, `g` `revert-buffer`, `q` `quit-window`.

### 7.4 `legu-dispatch` (transient)

```
legu — 61% read · 1.5% stale · 89.3% never read          snapshot 40s ago

 Read                      Move                     Store
  r  mark to point          n  next gap              k  forget region
  R  mark whole file        ]  next stale            t  attach ticket
  SPC set frontier          J  next file             T  visit ticket

 Query                     Repo
  .  describe at point      l  queue buffer          g  refresh
  s  diff stale region      c  coverage              h  toggle highlights

 -r --reviewer=jonas

 ?  help   q  quit
```

One transient, no sub-prefixes. Every key here is reachable from `C-c r`; the popup is a discoverability surface and the home of the one sticky infix.

The coverage line is a group `:description` lambda reading **the cached snapshot plist**. It never shells out — `:description` runs on every redisplay. `:refresh-suffixes t` so the numbers update after a mark. Scope is read as `(oref (transient-prefix-object) scope)`; `(transient-scope 'legu-dispatch)` is a `wrong-number-of-arguments` error against the transient bundled with Emacs 30.

`legu-visit-broken-store` appears as an extra suffix only when the root is in the `error` state.

---

## 8. The daily loop

Assume `(global-legu-mode 1)` and `(repeat-mode 1)`.

### 8.1 Resume reading

```
C-c r l          *legu* renders instantly from the cached snapshot; if none
                 exists, the header says "snapshot: loading…" and fills in
                 ~0.7s later.  Zero blocking.
n n RET          visit src/aishell/api/handlers.clj at line 1.
```

The buffer opens. Tier 0 fires: no sidecar → no glyphs, and the frontier triangle lands on line 1. Mode line ` legu 61%▪3`. **Subprocesses spawned by opening the file: zero.**

From anywhere without the queue buffer: `M-g M-n`, or `C-c r J`.

### 8.2 Mark a chunk

Read 60 lines. Point on line 60. `C-c r r`.

`legu-mark`, in order:

1. **Target, strict priority:**
   1. Active region → whole-line extended; a region ending at column 0 excludes that line.
   2. No region → frontier line + 1 … line at point.
   3. `C-u` → whole file, no range argument.
   4. `C-u C-u` → `read-string` for `START-END`, defaulting to the DWIM span.
2. **Frontier guards** (case 2 only):
   - Point **above** the frontier → `user-error`:
     `legu: point is above the reading frontier; select a region or press C-c r SPC`.
     A backward mark is a mistake, not an instruction.
   - Span > `legu-frontier-max` (400) → `y-or-n-p` naming the exact line count and range, once, before anything else happens.
3. **Save** per `legu-save-before-mark` (§6.4).
4. **Refuse** if the root is in the broken-store state, naming the file.
5. **Paint immediately in the `legu-unverified` style** — an in-flight mark is visually distinct from a confirmed one. Echo `marked src/aishell/api/handlers.clj:1-60`.
6. Move the frontier to the line after the region.
7. Enqueue `("mark" "src/aishell/api/handlers.clj:1-60")` on the root FIFO.
8. **On exit 0:** promote the overlays to the `legu-reviewed` style, apply the tier-2 patch, schedule the debounced snapshot refresh, run `legu-after-mark-hook`.
   **On non-zero:** delete the overlays, revert the frontier, `message` the exact stderr line in `warning` face, append to `*legu-failures*`.
9. If the span exceeds `legu-large-region-lines` (200), once per Emacs session:
   `legu: mark regions you can hold in your head — a whole region goes stale when any line in it changes`.

Then, with `repeat-mode`:

```
n                point to line 61
… read …
r                mark 61-134
n r n r          and so on
```

Two keystrokes per chunk after the first.

### 8.3 Hit a stale region

The bar goes dashed and the background tints.

```
C-c r ]          legu-next-stale — point on the region start
C-c r s          *legu-diff* opens in a bottom side window at the changed hunk
SPC SPC          read it
r                re-marks the region, closes the window, restores the layout,
                 repaints the source green
```

Tangled change: `e` from the diff buffer for `ediff` against the reviewed commit. Genuine re-read needed: `q`, then read in the source buffer and `C-c r r` — a re-mark of the exact same range supersedes the old record cleanly (`same-region?`, legu:496).

### 8.4 File a ticket

```
C-c r t          "Ticket for src/aishell/core.clj:112-130: " with completion
lgu-01k7 RET     enqueued; the note dot appears on line 112 when it lands
```

Completion candidates come from `legu-ticket-completion-function`. `C-c r T` on the region opens the ticket via `legu-ticket-visit-function`. The package never stores prose and never creates a ticket.

### 8.5 Check progress

Passive: the mode line, always. Active:

```
C-c r c          legu: 133081 eligible lines · 9.1% read · 1.5% stale ·
                 89.3% never read  (snapshot 40s ago)
C-u C-c r c      refresh first, then report
C-c r l          the three numbers as three bars, permanently
```

The snapshot age is always stated. A cached number the user can date beats a spinner.

### 8.6 Sweep a directory of small files

```
C-c r l          queue
C-s ops/ RET     find the block
C-SPC            set mark, move down four rows
r                "Mark 4 files reviewed? (y or n)" → four whole-file marks
                 enqueued in order on the root FIFO, one refresh at the end
```

---

## 9. Dependencies

```elisp
;; Package-Requires: ((emacs "30.1") (transient "0.7.2"))
```

- **Emacs 30.1** — the 29.1 overlay interval-tree rewrite (makes per-line glyph overlays free), native `json-parse-buffer` with no libjansson question, `left-fringe-help` fringe tooltips, `window-buffer-change-functions`. `compat` would buy Emacs 28 at the cost of the old overlay implementation; not worth it.
- **transient 0.7.2** — the version bundled with Emacs 30.2 is 0.7.2.2, so this requirement **downloads nothing**. The code stays strictly inside the 0.7 API: no `transient-define-group`, no `transient-inline-group`, no `transient-active-prefix`, and scope read via `(oref (transient-prefix-object) scope)`. It replaces the manual for sixteen commands; the alternative (`which-key`) is a real dependency for less.
- Core, no declaration needed: `compilation-mode`, `diff-mode`, `ediff`, `filenotify`, `vc`, `json`, `seq`, `subr-x`.

**Rejected:** `magit-section` (four transitive packages — `compat`, `cond-let`, `llama`, `seq` — plus an undeclared load-time requirement on transient ≥ 0.13 that prints an "Emergency (magit)" banner against the bundled 0.7.2.2, all to fold a tree this package does not draw). `dash`/`s`/`f` (`seq` and the built-in `string-*`/`file-*` cover everything). `fringe-helper` (`define-fringe-bitmap` with a literal vector and the `(center t)` periodic align form is three lines). `project.el` as the root oracle (§3.1). `parseedn` (the reader is 70 lines over a format `pprint` produces).

License: GPL-3.0-or-later.

Every file carries `;;; -*- lexical-binding: t -*-`. Without the cookie the process sentinels do not capture their lexical environment and fail with `Symbol's value as variable is void` from inside the sentinel, where the backtrace is useless.

---

## 10. Test plan

### 10.1 ERT — pure, no binary, no git (`legu-tests.el`, prefix `legu-test-`)

**Range parsing**
- `legu--parse-ranges` on `"40-95,120"` → `((40 . 95) (120 . 120))`; on `"-"` → nil; on `""` → nil; on nil → nil; on `"1"` → `((1 . 1))`.
- Round-trip: complement of ranges within `1..total` and back.

**EDN reader**
- Parses a real pprinted sidecar fixture: nested maps, vectors, keywords, strings with `\"` and `\\`, integers, `true`, `nil`.
- Returns nil (never signals) on: conflict markers, truncated input, an unsupported reader tag, a top-level vector.
- `:schema 2` ⇒ `legu--sidecar-records` returns nil.

**Derived arithmetic**
- `legu--coverage-from-rows` on a fixture row set equals hand-computed `(:files :lines :reviewed :stale :never)`, including `never = lines - reviewed - stale`.
- `legu--queue` ordering: `("src/a.clj" "src-x/b.clj" "a.clj" "src/api/c.clj")` sorts exactly as `(sort-by (juxt parent path))` does — the trailing-slash strip is asserted explicitly with the `"src"` / `"src-x"` pair.
- `legu--queue` filters out rows with `unreviewed + stale = 0` and respects `limit`.

**Snapshot trust**
- `legu--snapshot-trusted-p`: false when the file mtime is newer than `:started`, true when older, false when the snapshot is nil.

**Painting precedence**
- Given tier-0 verified `((10 . 20))`, snapshot reviewed `((10 . 20) (40 . 50))`, snapshot stale `((15 . 25))`, trusted: reviewed = `((10 . 20) (40 . 50))`, stale = `((21 . 25))`, unreviewed = the rest.
- Same inputs, untrusted snapshot: reviewed = `((10 . 20))`, stale = nil.

**Overlay lifecycle** (in a temp buffer)
- `legu--paint` then `legu--clear` leaves zero overlays with the `legu` property.
- Deleting the text under a region leaves no live zero-length overlay (`evaporate`).
- Inserting at the end boundary of a reviewed region does not extend it (`rear-advance` nil).
- Cut-and-yank a reviewed region: the yanked text carries no `legu-state`.
- `legu--enter-unverified` re-faces every overlay and deletes none.

**Mode line**
- `legu--lighter` for each of: normal, `?` untrusted, `?` modified, `!` broken, `—` out of scope. Assert `(get 'legu-lighter 'risky-local-variable)` is non-nil.

**JSON edge cases** (fed as strings to the parser wrapper)
- `stale[]` entry with `"start":null` and one with `start` absent both yield nil bounds.
- `notes[]` opaque entry with no `start`/`end`.
- `:false-object nil` — a `false` value is nil, not truthy.
- Malformed JSON → the wrapper returns nil and records an error, does not signal.

**Frontier guards**
- Point above the frontier signals `user-error`.
- Span > `legu-frontier-max` calls `y-or-n-p`; answering no issues no process.
- The `legu-large-region-lines` nudge fires once per session, not twice.

**Failure path**
- A simulated non-zero sentinel deletes the optimistic overlays, reverts the frontier, and appends exactly one `*legu-failures*` row.

### 10.2 Integration — real scratch git repo, real `legu` binary

Fixture macro `legu-test-with-repo`: `make-temp-file` directory, `git init`, `git config user.name/user.email`, write files, `git add -A && git commit`, run the real `legu-executable`, tear down. **Every test in this section skips (`ert-skip`) when `(executable-find legu-executable)` is nil**, so the suite passes on a machine without babashka.

1. **`file-hash` reproduction — the drift detector.** Mark a region with the real binary in a file containing tabs, trailing whitespace, a CRLF line, a non-ASCII byte, and a final newline. Read the sidecar, assert `legu--file-hash` equals the recorded `:file-hash` exactly. Repeat for a file with no trailing newline and for a 1-byte file. **This is the single test that catches upstream drift on the day it lands.**
2. **Tier-0 correctness.** Mark `a.txt:10-20`; assert the elisp paints reviewed at exactly 10–20 with zero processes. Then edit line 15 and save; assert tier 0 paints *nothing* for that record (not stale) and requests a refresh.
3. **Tier-0 per-record partiality.** Two regions in one file; change one region's content so only one `:file-hash` still matches — wait, `file-hash` is whole-file, so instead: two sidecars, one file changed. Assert the unchanged file paints fully and the changed one paints nothing, and that no sidecar's failure suppresses the other.
4. **Snapshot round trip.** Mark several regions across three files, stale one of them by editing; run the real `status --json` and `stale --json` through the sentinel path; assert the derived coverage plist equals the real `legu coverage --json` output field for field (`eligible-files`, `eligible-lines`, `never-read`, `reviewed`, `stale`), and the derived queue equals the real `legu next --json --limit 50` output row for row including order and `ranges`. **This is the test that licenses never invoking `coverage` or `next`.**
5. **stderr-with-exit-0.** `git add` nothing; `legu mark untracked.txt` through the process layer. Assert exit 0, stdout parses, stderr carries the "not tracked by git" warning, and the package treats it as a warning that does not fail the mark.
6. **`{"files":[],"notes":[]}`.** `status --json` on an untracked path; assert the package renders out-of-scope and paints nothing.
7. **Broken store.** Write conflict markers into a sidecar; assert every command exits 1 with empty stdout, the stderr regexp matches, the root enters `error`, the previous snapshot is retained, writes are refused, and tier 0 still paints the *other* files.
8. **Range-shaped and awkward paths.** Mark `"weird dir/spa ce'quote\"and:12-14.txt"` through the argv path; assert it succeeds and the returned `"path"` matches. Assert it is never passed through a shell.
9. **Unsaved-buffer refusal.** Buffer with 6 lines, file with 3; `legu-mark` with `legu-save-before-mark` nil signals `user-error` and spawns nothing. With `t`, it saves and the mark records the 6-line content.
10. **Whitespace insensitivity.** Mark a region, run `delete-trailing-whitespace`, save, refresh; assert the region is still reviewed and not stale (`norm-hash` trims per line, legu:131–134).
11. **Rename blind spot, documented behaviour.** `git mv a.txt b.txt`, commit. Assert tier 0 on `b.txt` paints nothing, and that after the snapshot lands the region paints reviewed at its projected range. This test asserts the *documented limit*, so a future fix breaks it visibly.
12. **Write serialization.** Enqueue two marks in *different* files back to back; assert both records survive (no lost update through `purge!`'s cross-sidecar rewrite) and that exactly one process was in flight at a time.
13. **`next-error` bridge.** Render a queue buffer from a real snapshot; assert `M-g M-n` from an unrelated buffer visits the first row's path at its start line.
14. **CLI contract guard.** Assert `legu --help` exits 0 and its usage text still names all seven commands and the `--json`, `--reviewer`, `--limit` flags. This is the canary for a CLI upgrade that changes the surface out from under the package.

---

## 11. Known limits and deliberate omissions

1. **Rename blind spot.** Tier 0 reads one sidecar keyed by the current path, so a region read under an old name paints as unread until the next snapshot lands (seconds, bounded by the `.review/` watcher and the post-write debounce). Documented in the README; test 11 asserts it.
2. **The optimistic window.** A mark is painted before the CLI confirms it. It is painted in the `unverified` style until exit 0, failures revert and are logged to `*legu-failures*`, and writes are serialized — but there is a window in which the screen shows a claim the store has not accepted. CLI-1 shrinks that window from 2.7s to ~0.1s.
3. **Ghost regions are shown, never repaired.** A mark that partially overlaps an existing record leaves both, per legu's own semantics (`superseded?` requires an exact match). They appear as separate `stale` rows. The package will not issue `forget` to tidy them.
4. **A corrupt sidecar for the current file kills that file's display.** Tier 0 and the CLI fail on the same file; the package names it and offers to open it rather than pretending.
5. **Paths containing `:` are not `next-error`-navigable** in the queue buffer. `RET` still works (text properties are authoritative).
6. **The snapshot can be minutes old.** Its age is always displayed. Nothing blocks on it.
7. **No Tramp.** `legu-mode` refuses on remote files.
8. **No `--version` handshake** until CLI-2 lands; the package probes `--help` and reads `:schema`.
9. **Margins have no priority ordering.** Under `legu-indicator-style` `margin`, glyphs from multiple providers concatenate; the package takes exactly one column.
10. **`legu-header-line-mode` is off by default** and costs a screen line when on.
11. **Everything in §1's NON-goals list.** In particular: no dashboard, no prose, no approval flow, no batch flag/execute, no client-side region arithmetic, no ghost-diff renderer, no `legu-mark-defun`, no ticket creation, no auto-mark-on-dwell, and no writing of `.review/` from Emacs.