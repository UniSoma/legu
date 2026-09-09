;;; legu.el --- Review coverage for a codebase  -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Jonas Rodrigues

;; Author: Jonas Rodrigues <313741+jxonas@users.noreply.github.com>
;; Version: 0.1.0
;; Package-Requires: ((emacs "30.1") (transient "0.7.2"))
;; Keywords: tools, vc
;; URL: https://github.com/UniSoma/legu

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;;; Commentary:

;; `legu.el' is a fringe gutter plus one keystroke.  It is the reading
;; analogue of `diff-hl': a buffer-local minor mode paints which lines of
;; the file you are looking at have been read, and which have been read
;; but have since changed.  `legu-mark' (C-c r r) means "everything from
;; where I left off down to here, I have now read".
;;
;; All state lives in the repository, in `.review/', written only by the
;; `legu' command line tool.  This package never writes there itself.
;;
;;   (global-legu-mode 1)
;;   (repeat-mode 1)   ; makes the reading loop  C-c r r  then  n r n r

;;; Code:

(require 'seq)
(require 'subr-x)
(require 'vc-hooks)
(require 'filenotify)
(require 'legu-overlay)

(autoload 'legu-list "legu-list" "Show the reading queue." t)
(autoload 'legu-list-refresh-buffers "legu-list" "Re-render queue buffers.")
(autoload 'legu-dired-mode "legu-dired" "Show review coverage in dired." t)
(autoload 'legu-dired-eligible-p "legu-dired" "Whether dired can carry the column.")
(autoload 'legu-dired-refresh-buffers "legu-dired" "Re-render dired buffers.")
(autoload 'legu-diff-stale "legu-diff" "Diff a stale region." t)
(autoload 'legu-dispatch "legu-transient" "The legu menu." t)


;;;; Customization
;;
;; The `legu' group itself is defined in legu-overlay.el, which loads first.

;; Forward declaration: the minor mode is defined at the bottom of this file.
(defvar legu-mode)

(defcustom legu-executable "legu"
  "Name or absolute path of the legu command line tool."
  :type 'string
  :group 'legu)

(defcustom legu-reviewer nil
  "Who is doing the reading.  Nil lets legu ask git for the answer."
  :type '(choice (const :tag "git config user.name" nil) string)
  :group 'legu)

(defcustom legu-save-before-mark t
  "What to do when a mutating command runs in a modified buffer.
legu reads the file on disk, so acting on an unsaved buffer would
record content the user never read.  t saves silently, `ask'
prompts, nil refuses."
  :type '(choice (const :tag "Save silently" t)
                 (const :tag "Ask" ask)
                 (const :tag "Refuse" nil))
  :group 'legu)

(defcustom legu-frontier-max 400
  "Confirm before marking a frontier span longer than this many lines."
  :type 'integer
  :group 'legu)

(defcustom legu-large-region-lines 200
  "Nudge about region size once per session above this many lines."
  :type 'integer
  :group 'legu)

(defcustom legu-snapshot-initial-delay 2.0
  "Idle seconds before the first snapshot refresh in a repository."
  :type 'number
  :group 'legu)

(defcustom legu-snapshot-debounce 5.0
  "Seconds to wait after writes settle before refreshing the snapshot."
  :type 'number
  :group 'legu)

(defcustom legu-store-debounce 2.0
  "Seconds to wait after a `.review/' change before refreshing."
  :type 'number
  :group 'legu)

(defcustom legu-slow-root-threshold 1.5
  "A repository whose last refresh took longer than this is slow."
  :type 'number
  :group 'legu)

(defcustom legu-slow-root-debounce 15.0
  "Debounce used instead of the normal ones in a slow repository."
  :type 'number
  :group 'legu)

(defcustom legu-evil-integration t
  "Whether to bind the queue and diff buffers for evil, when evil is present.
Without this the queue buffer is not usable in normal state: see
`legu-evil-setup\='."
  :type 'boolean
  :group 'legu)

(defcustom legu-evil-source-motions t
  "Whether to add unimpaired-style motions to source buffers under evil.
Adds `]r\=' and `[r\=' for stale regions and `]g\=' and `[g\=' for gaps in
`legu-mode\=' buffers, in normal state.  Both pairs are unbound in evil,
evil-collection and Doom."
  :type 'boolean
  :group 'legu)

(defcustom legu-watch-store t
  "Whether to watch `.review/' for changes made outside Emacs."
  :type 'boolean
  :group 'legu)

(defcustom legu-dired-column t
  "Whether `global-legu-mode' shows the coverage column in dired buffers."
  :type 'boolean
  :group 'legu)

(defcustom legu-exclude-modes
  '(image-mode doc-view-mode archive-mode tar-mode hexl-mode special-mode)
  "Major modes `global-legu-mode' never turns `legu-mode' on in."
  :type '(repeat symbol)
  :group 'legu)

(defcustom legu-max-file-size 2000000
  "`global-legu-mode' skips files larger than this many bytes."
  :type 'integer
  :group 'legu)

(defcustom legu-next-limit 50
  "How many files the queue buffer lists."
  :type 'integer
  :group 'legu)

(defcustom legu-ticket-completion-function #'legu-known-tickets
  "Function returning a list of ticket ids to complete against."
  :type 'function
  :group 'legu)

(defcustom legu-ticket-visit-function #'legu-visit-ticket-default
  "Function called with a ticket id to display that ticket."
  :type 'function
  :group 'legu)

(defcustom legu-after-mark-hook nil
  "Hook run in the source buffer after a mark is confirmed by legu."
  :type 'hook
  :group 'legu)


;;;; Repository root

(defvar legu--root-cheap-cache (make-hash-table :test #'equal)
  "Memoized `locate-dominating-file' results, keyed by directory.")

(defun legu--root-cheap (dir)
  "Nearest ancestor of DIR holding a .review store, or nil.
Presence of the store is the opt-in signal: a repository that has
never run legu costs nothing on visit."
  (let* ((dir (file-name-as-directory (expand-file-name dir)))
         (hit (gethash dir legu--root-cheap-cache 'miss)))
    (if (eq hit 'miss)
        (puthash dir
                 (let ((d (locate-dominating-file dir ".review")))
                   (and d (expand-file-name d)))
                 legu--root-cheap-cache)
      hit)))

(defun legu-root (&optional file)
  "The legu repository root for FILE, mirroring the CLI's own search.
The git top level, else the nearest ancestor holding `.review/'."
  (let* ((file (or file buffer-file-name default-directory))
         (default-directory (if (file-directory-p file)
                                (file-name-as-directory file)
                              (or (file-name-directory file) default-directory))))
    ;; Not `vc-root-dir': it answers nil for a file git does not track yet,
    ;; and it reads the current buffer.  `.git' matches as a directory or as
    ;; the file a worktree and a submodule use, which is what git itself does.
    (when-let* ((root (or (locate-dominating-file default-directory ".git")
                          (locate-dominating-file default-directory ".review"))))
      (expand-file-name (file-name-as-directory root)))))

(defun legu--relative (root file)
  "FILE as a repository-relative path under ROOT."
  (file-relative-name (expand-file-name file) root))


;;;; Line ranges
;;
;; A range set is a list of (START . END) conses, inclusive, sorted and
;; non-overlapping.

(defun legu--ranges-normalize (ranges)
  "Sort and merge RANGES into a canonical range set."
  (let (out)
    (dolist (r (sort (copy-sequence ranges)
                     (lambda (a b) (or (< (car a) (car b))
                                       (and (= (car a) (car b)) (< (cdr a) (cdr b)))))))
      (if (and out (<= (car r) (1+ (cdar out))))
          (setcdr (car out) (max (cdar out) (cdr r)))
        (push (cons (car r) (cdr r)) out)))
    (nreverse out)))

(defun legu--ranges-union (a b)
  "Union of range sets A and B."
  (legu--ranges-normalize (append a b)))

(defun legu--ranges-subtract (a b)
  "Range set A with every line in range set B removed."
  (let ((result (mapcar (lambda (r) (cons (car r) (cdr r)))
                        (legu--ranges-normalize a))))
    (dolist (cut (legu--ranges-normalize b))
      (let (next)
        (dolist (r result)
          (cond
           ((or (< (cdr r) (car cut)) (> (car r) (cdr cut))) (push r next))
           (t
            (when (< (car r) (car cut)) (push (cons (car r) (1- (car cut))) next))
            (when (> (cdr r) (cdr cut)) (push (cons (1+ (cdr cut)) (cdr r)) next)))))
        (setq result (legu--ranges-normalize next))))
    result))

(defun legu--ranges-complement (ranges total)
  "Lines 1..TOTAL not covered by RANGES."
  (if (< total 1) nil (legu--ranges-subtract (list (cons 1 total)) ranges)))

(defun legu--ranges-count (ranges)
  "How many lines RANGES covers."
  (apply #'+ (mapcar (lambda (r) (1+ (- (cdr r) (car r)))) ranges)))

(defun legu--ranges-member (ranges line)
  "The range in RANGES containing LINE, or nil."
  (seq-find (lambda (r) (and (<= (car r) line) (<= line (cdr r)))) ranges))

(defun legu--parse-ranges (s)
  "Parse legu's formatted range string S into a list of (START . END).
S is display output: comma-joined \"a-b\" spans and bare \"a\" lines,
with the literal string \"-\" for the empty set.  The day legu emits
structured pairs, this is the only call site to change."
  (unless (or (null s) (equal s "-") (equal s ""))
    (mapcar (lambda (c)
              (if (string-match "\\`\\([0-9]+\\)-\\([0-9]+\\)\\'" c)
                  (cons (string-to-number (match-string 1 c))
                        (string-to-number (match-string 2 c)))
                (let ((n (string-to-number c))) (cons n n))))
            (split-string s "," t))))

(defun legu-format-ranges (ranges)
  "Render RANGES the way the legu CLI does."
  (if (null ranges) "-"
    (mapconcat (lambda (r) (if (= (car r) (cdr r))
                               (number-to-string (car r))
                             (format "%d-%d" (car r) (cdr r))))
               ranges ",")))


;;;; The sidecar reader
;;
;; Strictly read only.  Nothing in this package writes .review/.

(defun legu--file-hash (file)
  "SHA-256 of FILE's bytes, the way legu computes :file-hash."
  (when (file-regular-p file)
    (with-temp-buffer
      (set-buffer-multibyte nil)
      (insert-file-contents-literally file)
      (secure-hash 'sha256 (current-buffer)))))

(defun legu--edn-skip (s i)
  "Index of the next significant character in S at or after I.
Whitespace, commas and line comments are insignificant in EDN."
  (let ((n (length s)))
    (while (and (< i n)
                (let ((c (aref s i)))
                  (cond
                   ((memq c '(?\s ?\t ?\n ?\r ?,)) t)
                   ((eq c ?\;) (while (and (< i n) (not (eq (aref s i) ?\n)))
                                 (setq i (1+ i)))
                    t)
                   (t nil))))
      (setq i (1+ i)))
    i))

(defun legu--edn-token (s i)
  "Read the bare token in S starting at I.  Returns (TEXT . NEXT)."
  (let ((n (length s)) (start i))
    (while (and (< i n)
                (not (memq (aref s i)
                           '(?\s ?\t ?\n ?\r ?, ?\{ ?\} ?\[ ?\] ?\( ?\) ?\"))))
      (setq i (1+ i)))
    (cons (substring s start i) i)))

(defun legu--edn-string (s i)
  "Read the string in S whose opening quote is at I.  Returns (VALUE . NEXT)."
  (let ((n (length s)) (i (1+ i)) (out nil) (done nil))
    (while (and (not done) (< i n))
      (let ((c (aref s i)))
        (cond
         ((eq c ?\") (setq done t i (1+ i)))
         ((eq c ?\\)
          (setq i (1+ i))
          (when (< i n)
            (push (pcase (aref s i)
                    (?n ?\n) (?t ?\t) (?r ?\r) (?f ?\f) (?b ?\b)
                    (?\\ ?\\) (?\" ?\") (c c))
                  out)
            (setq i (1+ i))))
         (t (push c out) (setq i (1+ i))))))
    (and done (cons (apply #'string (nreverse out)) i))))

(defun legu--edn-read (s i)
  "Read one EDN value from S at index I.  Returns (VALUE . NEXT), or nil.
Nil means the input is not something this reader understands, which
downgrades the caller rather than signalling."
  (let ((i (legu--edn-skip s i)))
    (when (< i (length s))
      (pcase (aref s i)
        (?\" (legu--edn-string s i))
        (?\{ (legu--edn-read-map s (1+ i)))
        (?\[ (legu--edn-read-seq s (1+ i) ?\]))
        (?\( (legu--edn-read-seq s (1+ i) ?\)))
        ((or ?\} ?\] ?\)) nil)
        (_ (let* ((tok (legu--edn-token s i))
                  (text (car tok)))
             (cond
              ((equal text "") nil)
              ((equal text "nil") (cons nil (cdr tok)))
              ((equal text "true") (cons t (cdr tok)))
              ((equal text "false") (cons nil (cdr tok)))
              ((string-prefix-p ":" text) (cons (intern (substring text 1)) (cdr tok)))
              ((string-match-p "\\`[-+]?[0-9]+N?\\'" text)
               (cons (string-to-number text) (cdr tok)))
              ((string-match-p "\\`[-+]?[0-9]*\\.[0-9]+M?\\'" text)
               (cons (string-to-number text) (cdr tok)))
              ;; Anything else -- symbols, reader tags, sets -- is a shape
              ;; this store never contains.  Refuse the whole file.
              (t nil))))))))

(defun legu--edn-read-seq (s i close)
  "Read EDN values from S at I until CLOSE.  Returns (LIST . NEXT)."
  (let ((items nil) (done nil) (fail nil))
    (while (and (not done) (not fail))
      (setq i (legu--edn-skip s i))
      (cond
       ((>= i (length s)) (setq fail t))
       ((eq (aref s i) close) (setq done t i (1+ i)))
       (t (let ((v (legu--edn-read s i)))
            (if v (progn (push (car v) items) (setq i (cdr v)))
              (setq fail t))))))
    (unless fail (cons (nreverse items) i))))

(defun legu--edn-read-map (s i)
  "Read an EDN map from S at I.  Returns (ALIST . NEXT).
Keyword keys become plain symbols, so :file-hash reads as `file-hash'."
  (let ((pairs nil) (done nil) (fail nil))
    (while (and (not done) (not fail))
      (setq i (legu--edn-skip s i))
      (cond
       ((>= i (length s)) (setq fail t))
       ((eq (aref s i) ?\}) (setq done t i (1+ i)))
       (t (let ((k (legu--edn-read s i)))
            (if (not k) (setq fail t)
              (let ((v (legu--edn-read s (cdr k))))
                (if (not v) (setq fail t)
                  (push (cons (car k) (car v)) pairs)
                  (setq i (cdr v)))))))))
    (unless fail (cons (nreverse pairs) i))))

(defun legu--read-edn (text)
  "Parse TEXT, one pprinted legu sidecar, into an alist.  Never signals.
A sidecar is a map; anything else -- a bare vector, a reader tag, a
half-written merge conflict -- reads as nil and downgrades the caller."
  (condition-case nil
      (let ((start (legu--edn-skip text 0)))
        (when (and (< start (length text)) (eq (aref text start) ?\{))
          (let ((v (legu--edn-read text start)))
            (and v (consp (car v)) (car v)))))
    (error nil)))

(defun legu-sidecar-file (root relpath)
  "Absolute path of the sidecar recording RELPATH under ROOT."
  (expand-file-name (concat ".review/" relpath ".edn") root))

(defconst legu-sidecar-schema 2
  "The sidecar schema this package reads, the one the CLI writes.")

(defvar legu--schema-warned nil
  "Roots already warned about an unreadable store schema.")

(defun legu-sidecar-records (root relpath)
  "Records stored for RELPATH under ROOT, as a plist.
The plist has `:regions' and `:tickets', each a list of alists, and
`:ok' which is nil when the sidecar exists but could not be read.  Only
the schema the CLI writes today is read, exactly as the CLI itself does."
  (let ((file (legu-sidecar-file root relpath)))
    (if (not (and (file-regular-p file) (file-readable-p file)))
        (list :regions nil :tickets nil :ok t)
      (let* ((text (with-temp-buffer
                     (insert-file-contents file)
                     (buffer-string)))
             (data (legu--read-edn text)))
        (cond
         ((null data) (list :regions nil :tickets nil :ok nil))
         ((not (eql legu-sidecar-schema (alist-get 'schema data)))
          (unless (member root legu--schema-warned)
            (push root legu--schema-warned)
            (message "legu: sidecar schema %s is not the %s this package reads; painting from the CLI only"
                     (alist-get 'schema data) legu-sidecar-schema))
          (list :regions nil :tickets nil :ok nil))
         (t (list :regions (alist-get 'regions data)
                  :tickets (alist-get 'tickets data)
                  :ok t)))))))


;;;; Tier 0: the sidecar plus a file hash, with no subprocess at all

(defun legu--tier0 (root relpath file)
  "Review state for FILE derivable locally.  Returns a plist.

`:reviewed' are ranges legu itself would report reviewed without any
projection -- records whose stored `:file-hash' still matches the file,
which is exactly the first branch of the CLI's anchoring.  `:tickets' are
the first lines of matching ticket references.  `:unresolved' is non-nil when
some record could not be confirmed, which is a request for a snapshot,
never a verdict of staleness."
  (let* ((records (legu-sidecar-records root relpath))
         (hash (and (plist-get records :ok)
                    (or (plist-get records :regions) (plist-get records :tickets))
                    (legu--file-hash file)))
         (reviewed nil) (tickets nil) (unresolved nil))
    (dolist (r (plist-get records :regions))
      (let ((start (alist-get 'start r)) (end (alist-get 'end r)))
        (if (and hash start end (equal hash (alist-get 'file-hash r)))
            (push (cons start end) reviewed)
          (setq unresolved t))))
    (dolist (tk (plist-get records :tickets))
      (let ((start (alist-get 'start tk)))
        (if (and hash start (equal hash (alist-get 'file-hash tk)))
            (push start tickets)
          (setq unresolved t))))
    (list :reviewed (legu--ranges-normalize reviewed)
          :tickets (sort tickets #'<)
          :unresolved unresolved
          :hash hash
          :ok (plist-get records :ok))))

(defun legu-region-record-at (root relpath line)
  "The stored region record covering LINE of RELPATH under ROOT, or nil.
Records are read from the sidecar, so this reports the region as it was
reviewed -- reviewer, timestamp and the commit a diff should run from."
  (let ((records (plist-get (legu-sidecar-records root relpath) :regions))
        (best nil))
    (dolist (r records)
      (let ((s (alist-get 'start r)) (e (alist-get 'end r)))
        (when (and s e (<= s line) (<= line e)
                   (or (null best)
                       (< (- e s) (- (alist-get 'end best) (alist-get 'start best)))))
          (setq best r))))
    best))

(defun legu-tickets-at (root relpath line)
  "Ticket ids anchored at LINE of RELPATH under ROOT, as stored.
Ticket references are anchors of their own, independent of any review
record covering the same lines."
  (let ((out nil))
    (dolist (tk (plist-get (legu-sidecar-records root relpath) :tickets))
      (let ((s (alist-get 'start tk)) (e (alist-get 'end tk))
            (id (alist-get 'ticket tk)))
        (when (and s e id (<= s line) (<= line e))
          (push id out))))
    (sort (delete-dups out) #'string<)))

(defun legu-region-record-nearest (root relpath line)
  "The stored region record of RELPATH under ROOT lying nearest LINE.
A stale region is reported where it is *now*, which is often not where it
was recorded; asking for the record under point would miss it."
  (or (legu-region-record-at root relpath line)
      (let ((best nil) (best-key nil))
        (dolist (r (plist-get (legu-sidecar-records root relpath) :regions))
          (let ((s (alist-get 'start r)) (e (alist-get 'end r)))
            (when (and s e)
              (let ((key (max 0 (max (- s line) (- line e)))))
                (when (or (null best) (< key best-key))
                  (setq best r best-key key))))))
        best)))


;;;; The process layer

(defvar legu--generations (make-hash-table :test #'equal)
  "Latest requested snapshot generation, keyed by root.")
(defvar legu--snapshots (make-hash-table :test #'equal)
  "Cached repository snapshots, keyed by root.")
(defvar legu--write-queues (make-hash-table :test #'equal)
  "Pending write jobs, keyed by root.  Writes are serialized per root.")
(defvar legu--write-active (make-hash-table :test #'equal)
  "Whether a write is in flight, keyed by root.")
(defvar legu--refresh-timers (make-hash-table :test #'equal)
  "Debounce timers, keyed by root.")
(defvar legu--watchers (make-hash-table :test #'equal)
  "`file-notify' descriptors for .review, keyed by root.")
(defvar legu--warned-paths nil
  "Paths whose CLI warning has already been shown this session.")
(defvar legu--failures nil
  "Failed mutations, newest first.  Each is a plist.")

(defun legu--program ()
  "Absolute path of the legu executable, or nil."
  (or (and (file-name-absolute-p legu-executable)
           (file-executable-p legu-executable)
           legu-executable)
      (executable-find legu-executable)))

(defun legu--run (root args callback)
  "Run legu with ARGS in ROOT, calling CALLBACK when it exits.
CALLBACK receives (STATUS STDOUT STDERR), STATUS either `ok' or
`failed'.  Nothing in this package ever blocks on it."
  (let ((program (legu--program)))
    (if (not program)
        ;; Signalling here would strand the write queue: the job is already
        ;; popped and the root already marked busy.  Report it as a failure
        ;; and let the caller's own failure path run.
        (funcall callback 'failed ""
                 (format "legu: executable %S not found on `exec-path'"
                         legu-executable))
      (legu--check-version root)
      (let* ((default-directory root)
           (out (generate-new-buffer " *legu-out*" t))
           (err (generate-new-buffer " *legu-err*" t))
           (errp (make-pipe-process :name "legu-err" :buffer err
                                    :noquery t :sentinel #'ignore)))
      (make-process
       :name "legu" :buffer out :noquery t :connection-type 'pipe
       :stderr errp
       :command (cons program args)
       :sentinel
       (lambda (proc _event)
         (when (memq (process-status proc) '(exit signal))
           (unwind-protect
               (let* ((code (process-exit-status proc))
                      (ok (and (eq (process-status proc) 'exit) (= 0 code)))
                      (stdout (with-current-buffer out (buffer-string)))
                      (stderr (with-current-buffer err (buffer-string)))
                      (status (if ok 'ok 'failed)))
                 (funcall callback status stdout stderr))
             (when (process-live-p errp) (delete-process errp))
             (when (buffer-live-p out) (kill-buffer out))
             (when (buffer-live-p err) (kill-buffer err))))))))))

(defun legu--parse-json (text)
  "Parse TEXT as JSON into alists, or nil when it is not JSON."
  (condition-case nil
      (with-temp-buffer
        (insert text)
        (goto-char (point-min))
        (json-parse-buffer :object-type 'alist :array-type 'list
                           :null-object nil :false-object nil))
    (error nil)))

(defun legu--warn-once (key text)
  "Show TEXT once per KEY per session."
  (unless (member key legu--warned-paths)
    (push key legu--warned-paths)
    (message "%s" (string-trim text))))


;;;; The version handshake

(defconst legu-cli-minimum-version "0.4.1"
  "The oldest legu CLI this package knows how to speak to.")

(defvar legu--version-checked nil
  "Roots whose CLI has already been asked what it is, this session.")

(defun legu--check-version (root)
  "Ask ROOT's legu what it is, once a session.
Say so when the answer is not one this package recognises.  Nothing
waits on it: an unrecognised CLI is still driven, just with a warning."
  ;; The root is marked asked before the question is asked, so the handshake's
  ;; own `legu--run' does not ask it again, and again.
  (unless (member root legu--version-checked)
    (push root legu--version-checked)
    (legu--run
     root '("--version" "--json")
     (lambda (status stdout _stderr)
       (let* ((data (and (eq status 'ok) (legu--parse-json stdout)))
              (version (alist-get 'version data))
              (schema (alist-get 'schema data))
              (parsed (and (stringp version) (ignore-errors (version-to-list version)))))
         (cond
          ((null parsed)
           (message "legu: this legu names no version legu.el understands; it speaks to %s or newer"
                    legu-cli-minimum-version))
          ((version-list-< parsed (version-to-list legu-cli-minimum-version))
           (message "legu: this legu is %s, older than the %s legu.el speaks to; upgrade it"
                    version legu-cli-minimum-version))
          ((not (eql schema legu-sidecar-schema))
           (message "legu: this legu writes store schema %s, not the %s legu.el reads; painting from the CLI only"
                    schema legu-sidecar-schema))))))))


;;;; The snapshot

(defun legu-snapshot (root)
  "The cached snapshot for ROOT, however old, or nil."
  (gethash root legu--snapshots))

(defun legu--snapshot-put (root key value)
  "Set KEY to VALUE in ROOT's snapshot."
  (let ((s (or (legu-snapshot root) (list :state 'fresh))))
    (puthash root (plist-put s key value) legu--snapshots)))

(defun legu-snapshot-trusted-p (snapshot file)
  "Whether SNAPSHOT is newer than FILE, and so may pronounce on it.
Without this guard the union paints a lie: edit inside a reviewed
region and save, and a snapshot taken a minute ago still says reviewed."
  (let ((started (and snapshot (plist-get snapshot :started)))
        (mtime (and file (file-attribute-modification-time (file-attributes file)))))
    (and started mtime (time-less-p mtime started))))

(defun legu--snapshot-debounce (root)
  "How long to wait before refreshing ROOT, given how slow it is."
  (let ((d (plist-get (legu-snapshot root) :duration)))
    (if (and d (> d legu-slow-root-threshold))
        legu-slow-root-debounce
      legu-snapshot-debounce)))

(defun legu-refresh-snapshot (root &optional delay)
  "Refresh ROOT's snapshot, after DELAY seconds if given.
Coalesces: a pending refresh is rescheduled, never duplicated.  Never
starts while ROOT has writes in flight; those reschedule it on drain."
  (when-let* ((timer (gethash root legu--refresh-timers)))
    (cancel-timer timer)
    (remhash root legu--refresh-timers))
  (if (and delay (> delay 0))
      (puthash root
               (run-with-timer delay nil #'legu--snapshot-start root)
               legu--refresh-timers)
    (legu--snapshot-start root)))

(defun legu--snapshot-start (root)
  "Launch the two processes that make up a snapshot of ROOT."
  (remhash root legu--refresh-timers)
  (unless (or (gethash root legu--write-active)
              (gethash root legu--write-queues))
    (let* ((gen (1+ (or (gethash root legu--generations) 0)))
           (started (current-time))
           (previous (plist-get (legu-snapshot root) :state))
           (pending (list :gen gen :started started :left 2 :status nil :stale nil)))
      (puthash root gen legu--generations)
      (condition-case err
          (legu--snapshot-launch root gen pending)
        (error
         ;; A root stuck reporting "refreshing…" forever is worse than one
         ;; that says what went wrong.
         (legu--snapshot-put root :state previous)
         (legu--snapshot-refresh-lighters root)
         (signal (car err) (cdr err)))))))

(defun legu--snapshot-launch (root gen pending)
  "Start the two processes of generation GEN for ROOT, folding into PENDING."
  (legu--snapshot-put root :state 'refreshing)
  (legu--snapshot-refresh-lighters root)
  (dolist (spec '((:status . ("status" "--json"))
                  (:stale . ("stale" "--json"))))
    (let ((slot (car spec)))
      (legu--run
       root (cdr spec)
       (lambda (status stdout stderr)
         (when (= gen (or (gethash root legu--generations) 0))
           (plist-put pending slot (list status stdout stderr))
           (plist-put pending :left (1- (plist-get pending :left)))
           (when (= 0 (plist-get pending :left))
             (legu--snapshot-finish root pending))))))))

(defun legu--snapshot-error (root kind message)
  "Put ROOT into the error state described by KIND and MESSAGE.
Reserved for a snapshot that has no numbers at all.  A store the CLI
merely skipped part of lands in `:errors' instead, numbers and all."
  (legu--snapshot-put root :state 'error)
  (legu--snapshot-put root :error (list :kind kind :message message))
  ;; This snapshot has no numbers at all; a partial one's sidecar list would
  ;; read as the whole story.
  (legu--snapshot-put root :errors nil)
  (legu--warn-once (list kind message) (format "legu: %s" message)))

(defun legu--store-errors (&rest data)
  "The sidecars DATA say the CLI could not read, as plists, one per file."
  (let (out)
    (dolist (d data)
      (dolist (e (alist-get 'errors d))
        (let ((file (alist-get 'file e)))
          (unless (seq-find (lambda (o) (equal file (plist-get o :file))) out)
            (push (list :file file :reason (alist-get 'reason e)) out)))))
    (nreverse out)))

(defun legu--snapshot-finish (root pending)
  "Fold PENDING's two process results into ROOT's snapshot."
  (let* ((status (plist-get pending :status))
         (stale (plist-get pending :stale))
         (started (plist-get pending :started)))
    (cond
     ((or (eq (nth 0 status) 'failed) (eq (nth 0 stale) 'failed))
      (legu--snapshot-error
       root 'cli-failed
       (string-trim (or (and (eq (nth 0 status) 'failed) (nth 2 status))
                        (nth 2 stale) "legu exited non-zero"))))
     (t
      (let ((sdata (legu--parse-json (nth 1 status)))
            (tdata (legu--parse-json (nth 1 stale))))
        (if (or (null sdata) (null tdata))
            (legu--snapshot-error
             root 'bad-json
             (format "legu emitted unparseable output: %s"
                     (substring (nth 1 status) 0 (min 200 (length (nth 1 status))))))
          (legu--snapshot-store root sdata tdata started)))))
    (legu--snapshot-refresh-lighters root)
    (when (featurep 'legu-list) (legu-list-refresh-buffers root))
    (when (featurep 'legu-dired) (legu-dired-refresh-buffers root))))

(defun legu--snapshot-store (root sdata tdata started)
  "Build ROOT's snapshot from parsed SDATA and TDATA, launched at STARTED.
Sidecars the CLI could not read are carried in `:errors'; every number
here is live, and short by whatever those files held."
  (let ((rows (make-hash-table :test #'equal))
        (eligible (make-hash-table :test #'equal))
        (stale (make-hash-table :test #'equal))
        (tickets (make-hash-table :test #'equal))
        (files 0) (lines 0) (reviewed 0) (nstale 0)
        (queue nil))
    (dolist (f (alist-get 'files sdata))
      (let ((path (alist-get 'path f)))
        (puthash path t eligible)
        (puthash path
                 (list :total (or (alist-get 'total f) 0)
                       :reviewed (or (alist-get 'reviewed f) 0)
                       :stale (or (alist-get 'stale f) 0)
                       :unreviewed (or (alist-get 'unreviewed f) 0)
                       :ranges (legu--parse-ranges (alist-get 'ranges f)))
                 rows)
        (setq files (1+ files)
              lines (+ lines (or (alist-get 'total f) 0))
              reviewed (+ reviewed (or (alist-get 'reviewed f) 0))
              nstale (+ nstale (or (alist-get 'stale f) 0)))))
    (dolist (tk (alist-get 'tickets sdata))
      (let ((path (alist-get 'path tk)))
        (puthash path (cons (list (alist-get 'start tk) (alist-get 'end tk)
                                  (alist-get 'ticket tk) (alist-get 'state tk))
                            (gethash path tickets))
                 tickets)))
    (dolist (r (alist-get 'stale tdata))
      (let ((path (alist-get 'path r)))
        (puthash path (cons (list (alist-get 'start r) (alist-get 'end r)
                                  (alist-get 'reason r) (alist-get 'state r))
                            (gethash path stale))
                 stale)))
    (setq queue (legu--queue rows legu-next-limit))
    (puthash root
             (list :generation (gethash root legu--generations)
                   :started started
                   :duration (float-time (time-subtract (current-time) started))
                   :rows rows :eligible eligible :stale stale :tickets tickets
                   :coverage (list :files files :lines lines :reviewed reviewed
                                   :stale nstale :never (- lines reviewed nstale))
                   :queue queue
                   :state 'fresh :error nil
                   :errors (legu--store-errors sdata tdata))
             legu--snapshots)
    (dolist (e (legu--store-errors sdata tdata))
      (legu--warn-once (list 'store-error (plist-get e :file) (plist-get e :reason))
                       (format "legu: skipped %s (%s); its lines are missing from every number"
                               (plist-get e :file) (plist-get e :reason))))))

(defun legu--parent-key (path)
  "Reproduce the CLI's (str (fs/parent (fs/path PATH))) sort key.
No trailing slash, empty at the top level: \"src\" and \"src-x\" order
differently from \"src/\" and \"src-x/\"."
  (let ((d (file-name-directory path)))
    (if d (directory-file-name d) "")))

(defun legu--queue (rows limit)
  "The reading queue: LIMIT rows of ROWS with unread or stale lines.
Ordering reproduces the CLI's `next' exactly."
  (let (gaps)
    (maphash (lambda (path row)
               (when (> (+ (plist-get row :unreviewed) (plist-get row :stale)) 0)
                 (push (list :path path
                             :unreviewed (plist-get row :unreviewed)
                             :stale (plist-get row :stale)
                             :ranges (legu--ranges-complement
                                      (plist-get row :ranges)
                                      (plist-get row :total))
                             ;; The CLI compares strings the way Java does,
                             ;; over UTF-16 code units.
                             :key (legu--sort-key (legu--parent-key path))
                             :path-key (legu--sort-key path))
                       gaps)))
             rows)
    (seq-take
     (sort gaps (lambda (a b)
                  (let ((da (plist-get a :key)) (db (plist-get b :key)))
                    (if (equal da db)
                        (string< (plist-get a :path-key) (plist-get b :path-key))
                      (string< da db)))))
     limit)))

(defun legu--sort-key (s)
  "S as UTF-16 code units, so `string<' orders it the way the CLI does."
  (encode-coding-string s 'utf-16be))

(defun legu-coverage-numbers (root)
  "The three numbers for ROOT, as a plist, or nil without a snapshot."
  (plist-get (legu-snapshot root) :coverage))

(defun legu-known-tickets (&optional root)
  "Every ticket id in ROOT's snapshot."
  (let ((tickets (plist-get (legu-snapshot (or root (legu-root))) :tickets))
        (out nil))
    (when tickets
      (maphash (lambda (_p entries)
                 (dolist (e entries) (when (nth 2 e) (push (nth 2 e) out))))
               tickets))
    (sort (delete-dups out) #'string<)))


;;;; Optimistic local patching

(defun legu--patch-snapshot (root relpath &rest ops)
  "Apply OPS to ROOT's cached row for RELPATH without a refresh.
OPS is a plist of `:reviewed' and `:unreviewed' range sets.  The
generation is not bumped: the next real snapshot replaces this wholesale."
  (when-let* ((snapshot (legu-snapshot root))
              (rows (plist-get snapshot :rows))
              (row (gethash relpath rows)))
    (let* ((add (plist-get ops :reviewed))
           (drop (plist-get ops :unreviewed))
           (staleh (plist-get snapshot :stale))
           (was-reviewed (plist-get row :reviewed))
           (was-stale (plist-get row :stale))
           (total (plist-get row :total))
           (ranges (legu--ranges-subtract
                    (legu--ranges-union (plist-get row :ranges) add) drop)))
      ;; A re-mark answers the stale records it covers.
      (when add
        (puthash relpath
                 (seq-remove (lambda (e)
                               (and (nth 0 e) (legu--ranges-member add (nth 0 e))))
                             (gethash relpath staleh))
                 staleh))
      (let* ((stale-ranges
              (legu--ranges-normalize
               (delq nil (mapcar (lambda (e)
                                   (and (nth 0 e) (nth 1 e) (cons (nth 0 e) (nth 1 e))))
                                 (gethash relpath staleh)))))
             (stale-lines (legu--ranges-count (legu--ranges-subtract stale-ranges ranges)))
             (reviewed-lines (legu--ranges-count ranges))
             (cov (plist-get snapshot :coverage)))
        (plist-put row :ranges ranges)
        (plist-put row :reviewed reviewed-lines)
        (plist-put row :stale stale-lines)
        (plist-put row :unreviewed (max 0 (- total reviewed-lines stale-lines)))
        (plist-put cov :reviewed (+ (plist-get cov :reviewed) (- reviewed-lines was-reviewed)))
        (plist-put cov :stale (+ (plist-get cov :stale) (- stale-lines was-stale)))
        (plist-put cov :never (max 0 (- (plist-get cov :lines)
                                        (plist-get cov :reviewed)
                                        (plist-get cov :stale))))
        (plist-put snapshot :queue (legu--queue rows legu-next-limit))
        (puthash root snapshot legu--snapshots)))))


;;;; The write queue
;;
;; The CLI's purge! rewrites arbitrary sidecars, so two concurrent marks in
;; different files can both rewrite a third.  One writer per root, always.

(defun legu--enqueue-write (root args on-done)
  "Queue a legu mutation ARGS in ROOT.  ON-DONE gets (STATUS STDOUT STDERR)."
  (puthash root (append (gethash root legu--write-queues)
                        (list (list args on-done)))
           legu--write-queues)
  (legu--write-pump root))

(defun legu--write-pump (root)
  "Start the next queued write for ROOT if none is in flight."
  (unless (gethash root legu--write-active)
    (if-let* ((queue (gethash root legu--write-queues)))
        (let* ((job (car queue))
               (rest (cdr queue)))
          (if rest (puthash root rest legu--write-queues)
            (remhash root legu--write-queues))
          (puthash root t legu--write-active)
          (when rest
            (message "legu: %d write%s pending" (length rest)
                     (if (= 1 (length rest)) "" "s")))
          (let ((delivered nil))
            (condition-case err
                (legu--run root (car job)
                           (lambda (status stdout stderr)
                             (setq delivered t)
                             (remhash root legu--write-active)
                             (unwind-protect
                                 (funcall (cadr job) status stdout stderr)
                               (legu--write-pump root))))
              (error
               ;; A launch that never reached the process leaves the job popped
               ;; and the root marked busy; releasing both here is what keeps it
               ;; from stopping every future write and every future snapshot.
               ;; An error raised by the job's own callback is not that, and
               ;; must not deliver the callback a second time.
               (if delivered
                   (signal (car err) (cdr err))
                 (remhash root legu--write-active)
                 (unwind-protect
                     (funcall (cadr job) 'failed "" (error-message-string err))
                   (legu--write-pump root)))))))
      ;; Drained: this is when a refresh may run.
      (legu-refresh-snapshot root (legu--snapshot-debounce root)))))

(defun legu--record-failure (root verb args message)
  "Record a failed mutation for the failures buffer."
  (push (list :time (format-time-string "%H:%M:%S")
              :root root :verb verb :args args :message (string-trim message))
        legu--failures))


;;;; Buffer state

(defvar-local legu--root nil)
(defvar-local legu--relpath nil)
(defvar-local legu--frontier nil)
(defvar-local legu--unverified nil)
(defvar-local legu--scope 'unknown)
(defvar-local legu--stale-count 0)
(defvar-local legu--unaccounted nil
  "Whether some record here is accounted for by nothing legu currently trusts.")
(defvar-local legu--painted nil
  "Plist of the ranges last painted: `:reviewed', `:stale', `:total'.")
(defvar-local legu--hidden nil)
(defvar-local legu--content-seen nil
  "Cons of (HASH . TIME) recording when this content was first seen here.")
(defvar-local legu--regions-request 0
  "Generation of the newest `legu-describe-region' request in this buffer.")
(defvar-local legu--file-regions nil
  "This buffer's accepted per-file `legu regions' answer, or nil.
A plist of `:reviewed' `:stale' `:tickets' `:complete' and the `:hash' of
the file it describes.")
(defvar-local legu--file-regions-request 0
  "Generation of the newest per-file regions request in this buffer.")
(defvar-local legu--file-regions-wanted nil
  "Whether this buffer needs a per-file query that has not been answered.")

(defvar legu--nudged nil
  "Whether the region-size nudge has already fired this session.")

;;;; Tier 0.5: one `legu regions' for the file in front of you
;;
;; Between the sidecar and the repository snapshot.  It comes from the CLI,
;; so unlike tier 0 it may pronounce stale, moved or missing -- which is how
;; a file whose regions were read under a previous name paints at all before
;; a snapshot has run.

(defun legu--file-regions-parse (answer)
  "Ranges to paint from a parsed `legu regions --json' ANSWER.
A record the CLI could not anchor carries no range and paints nothing."
  (let (reviewed stale tickets)
    (dolist (r (alist-get 'regions answer))
      (let ((start (alist-get 'start r))
            (end (alist-get 'end r)))
        (when (and start end)
          (pcase (alist-get 'state r)
            ("reviewed" (push (cons start end) reviewed))
            ("stale" (push (cons start end) stale))))))
    (dolist (tk (alist-get 'tickets answer))
      (when-let* ((start (alist-get 'start tk)))
        (push start tickets)))
    (list :reviewed (legu--ranges-normalize reviewed)
          :stale (legu--ranges-normalize stale)
          :tickets (sort (delete-dups tickets) #'<)
          :complete (and (alist-get 'complete answer) t))))

(defun legu--snapshot-outranks-p (started)
  "Whether a snapshot this buffer trusts, newer than STARTED, already answers.
The repository snapshot is the higher tier: once it has landed and may
pronounce here, a per-file answer requested before it has nothing to add.

The test has to be the one `legu--compute\=' paints by.  A weaker one --
mtime alone -- would throw the answer away for a snapshot that then
declines to speak here, and leave the buffer painting nothing until the
next save."
  (let ((snapshot (legu-snapshot legu--root)))
    (and snapshot
         (legu--snapshot-vouches-p snapshot buffer-file-name)
         (not (time-less-p (plist-get snapshot :started) started)))))

(defun legu--file-regions-query (&optional buffer)
  "Ask the CLI for BUFFER's own anchors, asynchronously.
Nothing here blocks Emacs, and the answer is dropped unless it still
describes the file it was asked about: the same guard
`legu-describe-region' uses, plus the snapshot that may have overtaken it."
  (with-current-buffer (or buffer (current-buffer))
    (when (and legu--root legu--relpath buffer-file-name
               (not (buffer-modified-p)))
      (let* ((buf (current-buffer))
             (file buffer-file-name)
             (hash (legu--file-hash file))
             (tick (buffer-chars-modified-tick))
             (started (current-time))
             (request (setq legu--file-regions-request
                            (1+ legu--file-regions-request))))
        (legu--run
         legu--root (list "regions" legu--relpath "--json")
         (lambda (status stdout _stderr)
           (when (buffer-live-p buf)
             (with-current-buffer buf
               (when-let* (((= request legu--file-regions-request))
                           ((= tick (buffer-chars-modified-tick)))
                           ((equal hash (legu--file-hash file)))
                           ((not (legu--snapshot-outranks-p started)))
                           ((eq status 'ok))
                           (answer (legu--parse-json stdout)))
                 (setq legu--file-regions
                       (plist-put (legu--file-regions-parse answer) :hash hash))
                 (legu--repaint buf))))))))))

(defun legu--file-regions-here (trusted hash)
  "This buffer's per-file answer, if it still has something to say.
Nothing, when a snapshot TRUSTED here already answers -- that is the
higher tier, and it is the later reading.  A change to the file since the
answer was given retires the answer outright.

HASH is the file\='s current hash if tier 0 already had reason to compute
one; the file is hashed here only when it did not."
  (when legu--file-regions
    (if (equal (plist-get legu--file-regions :hash)
               (or hash (legu--file-hash buffer-file-name)))
        (and (not trusted) legu--file-regions)
      (setq legu--file-regions nil))))

(defun legu--file-regions-maybe-query ()
  "Run the per-file query if the last repaint found it needed.
Called from the three moments the file on disk can have become a
different file -- opening it, saving it, reverting it -- and not from
`legu--repaint\=', which also runs on a window change and a landing
snapshot, and would spawn a process for each."
  (when legu--file-regions-wanted (legu--file-regions-query)))

(defun legu--file-accounted-for-p (tier0)
  "Whether the local pass alone accounts for this file.
True only when the sidecar was readable, had something to say, and every
record in it was confirmed.  A file with no sidecar at its current path is
not accounted for -- that is the rename, and it is what tier 0.5 is for."
  (and (plist-get tier0 :ok)
       (plist-get tier0 :hash)
       (not (plist-get tier0 :unresolved))))

(defun legu--compute (&optional buffer)
  "State to paint in BUFFER, as a plist of `:reviewed' `:stale' `:tickets'.

Local computation may confirm \"reviewed, in place\".  It may never
pronounce \"stale\", \"moved\" or \"missing\": those verdicts come only
from the CLI, and only while it is still describing this file -- a
snapshot newer than the file, or a per-file answer no edit has overtaken."
  (with-current-buffer (or buffer (current-buffer))
    (let* ((root legu--root)
           (rel legu--relpath)
           (file buffer-file-name)
           (tier0 (legu--tier0 root rel file))
           (snapshot (legu-snapshot root))
           (trusted (legu--trusted-here snapshot file tier0))
           (per-file (legu--file-regions-here trusted (plist-get tier0 :hash)))
           (rows (plist-get snapshot :rows))
           (row (and rows (gethash rel rows)))
           (snap-reviewed (and trusted row (plist-get row :ranges)))
           (snap-stale (and trusted
                            (let (out)
                              (dolist (e (gethash rel (plist-get snapshot :stale)))
                                (when (and (nth 0 e) (nth 1 e)
                                           (equal (nth 3 e) "stale"))
                                  (push (cons (nth 0 e) (nth 1 e)) out)))
                              (legu--ranges-normalize out))))
           (reviewed (legu--ranges-union
                      (legu--ranges-union (plist-get tier0 :reviewed) snap-reviewed)
                      (plist-get per-file :reviewed)))
           (stale (legu--ranges-subtract
                   (legu--ranges-union snap-stale (plist-get per-file :stale))
                   reviewed))
           (tickets (plist-get tier0 :tickets)))
      (when (and trusted row)
        (dolist (e (gethash rel (plist-get snapshot :tickets)))
          (when (nth 0 e) (push (nth 0 e) tickets))))
      (setq tickets (append tickets (plist-get per-file :tickets)))
      ;; A complete per-file answer resolves what the sidecar left open; an
      ;; incomplete one is itself a reason to keep the indicator up.
      (setq legu--unaccounted
            (and (not trusted)
                 (if per-file
                     (not (plist-get per-file :complete))
                   (and (plist-get tier0 :unresolved) t))))
      (setq legu--file-regions-wanted
            (and (not trusted) (null per-file)
                 (not (legu--file-accounted-for-p tier0))))
      (setq legu--scope
            (cond ((null snapshot) 'unknown)
                  ((and (plist-get snapshot :eligible)
                        (gethash rel (plist-get snapshot :eligible))) 'in)
                  ((plist-get snapshot :eligible) 'out)
                  (t 'unknown)))
      (list :reviewed reviewed
            :stale stale
            :tickets (sort (delete-dups tickets) #'<)))))

(defun legu--snapshot-vouches-p (snapshot file)
  "Whether SNAPSHOT may pronounce on FILE, given what this buffer has watched.

Mtime alone is not enough in the one state where the snapshot claims more
than local computation can check: a file whose mtime was backdated -- by
an archive, an rsync, a `touch\=' -- would otherwise let a snapshot vouch
for content it never saw.  So a snapshot older than a change this buffer
watched happen may not vouch for it, however new its mtime claims to be."
  (and (legu-snapshot-trusted-p snapshot file)
       (or (null (cdr legu--content-seen))
           (time-less-p (cdr legu--content-seen)
                        (plist-get snapshot :started)))))

(defun legu--trusted-here (snapshot file tier0)
  "Whether SNAPSHOT may pronounce on FILE, given what TIER0 could confirm.
Records what this buffer has watched of the file, then asks
`legu--snapshot-vouches-p\='."
  (let ((hash (plist-get tier0 :hash)))
    (cond
     ;; First sight of this file.  An mtime is all there is to go on, which is
     ;; the ordinary case: open a file the last snapshot already covered.
     ((null legu--content-seen) (setq legu--content-seen (cons hash nil)))
     ;; The content changed while this buffer was watching.
     ((not (equal hash (car legu--content-seen)))
      (setq legu--content-seen (cons hash (current-time)))))
    (legu--snapshot-vouches-p snapshot file)))

(defun legu--repaint (&optional buffer)
  "Recompute and repaint BUFFER."
  (with-current-buffer (or buffer (current-buffer))
    (when (and legu-mode legu--root buffer-file-name)
      (if legu--hidden
          ;; Observation lapses with the indicators: a buffer that comes back
          ;; must re-observe before a snapshot may vouch for it.
          (progn (setq legu--content-seen nil) (legu-overlay-clear))
        (let* ((state (legu--compute))
               (total (legu--buffer-lines)))
          (setq legu--painted (append state (list :total total)))
          (setq legu--stale-count (length (plist-get state :stale)))
          (legu--ensure-frontier state total)
          (legu-overlay-paint
           :reviewed (plist-get state :reviewed)
           :stale (plist-get state :stale)
           :tickets (plist-get state :tickets)
           :frontier (and legu--frontier
                          (marker-position legu--frontier)
                          (legu--line-number legu--frontier))
           :unverified (or legu--unverified legu--unaccounted)
           :out-of-scope (eq legu--scope 'out))))
      (force-mode-line-update))))

(defun legu--ensure-frontier (state total)
  "Place the frontier at the first gap, given STATE and TOTAL lines."
  (unless (and legu--frontier (marker-position legu--frontier))
    (let* ((covered (plist-get state :reviewed))
           (gaps (legu--ranges-complement covered total))
           (line (max 1 (if gaps (car (car gaps)) total))))
      (setq legu--frontier (copy-marker (legu--line-position line) t)))))

(defvar evil-visual-beginning)
(defvar evil-visual-end)

(defun legu--visual-region ()
  "The (BEG . END) buffer positions evil's visual selection covers, or nil.

Emacs's region is not the selection evil draws.  A linewise `V\='
leaves mark and point on the same line, so `use-region-p\=' is nil and a
mark would silently fall back to the frontier; an inclusive `v\='
selection ends one character before its last selected character, so a
mark would drop the last line the user read.  `evil-visual-end\=' is the
exclusive end of what evil actually highlighted, which is the only thing
here that matches what the user saw."
  (when (and (bound-and-true-p evil-local-mode)
             (fboundp 'evil-visual-state-p)
             (evil-visual-state-p)
             (markerp (bound-and-true-p evil-visual-beginning))
             (markerp (bound-and-true-p evil-visual-end)))
    (let ((beg (marker-position evil-visual-beginning))
          (end (marker-position evil-visual-end)))
      (when (and beg end)
        (cons (min beg end) (max beg end))))))

(defun legu--selection-p ()
  "Whether the user has selected text, under evil or without it."
  (or (legu--visual-region) (use-region-p)))

(defun legu--line-position (line)
  "Buffer position of the start of file line LINE.
Narrowing is invisible to legu: the CLI counts lines in the file, so
every conversion here has to as well."
  (save-restriction
    (widen)
    (save-excursion (goto-char (point-min)) (forward-line (1- line)) (point))))

(defun legu--line-number (&optional pos)
  "File line number of POS, ignoring any narrowing."
  (line-number-at-pos (or pos (point)) t))

(defun legu--buffer-lines ()
  "Lines in this buffer, counted the way the CLI counts them.
A newline-terminated file does not have an extra empty last line, and
marking one would be rejected."
  (save-restriction
    (widen)
    (let ((n (line-number-at-pos (point-max) t)))
      (cond ((= (point-max) (point-min)) 0)
            ((eq (char-before (point-max)) ?\n) (1- n))
            (t n)))))

(defun legu--snapshot-refresh-lighters (root)
  "Repaint every legu buffer belonging to ROOT."
  (dolist (buf (buffer-list))
    (when (buffer-live-p buf)
      (with-current-buffer buf
        (when (and legu-mode (equal legu--root root))
          (legu--repaint buf))))))


;;;; The mode line

(defun legu--lighter ()
  "Mode line string.  Reads precomputed buffer locals only."
  (let* ((snapshot (legu-snapshot legu--root))
         (cov (plist-get snapshot :coverage))
         (lines (plist-get cov :lines)))
    (concat
     " legu"
     (cond
      ((eq (plist-get snapshot :state) 'error)
       (propertize "!" 'face 'legu-error))
      ((eq legu--scope 'out) (propertize " —" 'face 'legu-ignored))
      (legu--unverified "?")
      (t
       (concat
        (when (and lines (> lines 0))
          (format " %d%%" (/ (* 100 (plist-get cov :reviewed)) lines)))
        (when legu--unaccounted "?")
        (when (> legu--stale-count 0)
          (propertize (format "▪%d" legu--stale-count) 'face 'warning))
        (when (plist-get snapshot :errors)
          (propertize "!" 'face 'legu-error))))))))

(defvar legu-lighter '(:eval (legu--lighter)))
;; Without this the lighter renders nothing at all, silently.
(put 'legu-lighter 'risky-local-variable t)


;;;; Commands

(defun legu--assert-usable ()
  "Signal unless a mutation may run in this buffer."
  (unless legu--root (user-error "legu: not in a legu repository"))
  ;; The CLI splits on newlines only, so a CR-terminated file is one line to
  ;; it and N lines here.  Every range this buffer could name would mean
  ;; something else at the other end.
  (when (and buffer-file-coding-system
             (eq 2 (coding-system-eol-type buffer-file-coding-system)))
    (user-error "legu: %s has CR-only line endings, which legu counts as one line"
                (or legu--relpath (buffer-name))))
  (let ((snapshot (legu-snapshot legu--root)))
    (when (eq (plist-get snapshot :state) 'error)
      (user-error "legu: %s; fix it, then press %s"
                  (plist-get (plist-get snapshot :error) :message)
                  (key-description (kbd "C-c r g"))))))

(defun legu--ensure-saved ()
  "Save the buffer, or refuse, per `legu-save-before-mark'."
  (when (buffer-modified-p)
    (pcase legu-save-before-mark
      ('t (save-buffer))
      ('ask (if (y-or-n-p "legu reads the file on disk.  Save this buffer? ")
                (save-buffer)
              (user-error "legu: refusing to act on a modified buffer")))
      (_ (user-error
          "legu: refusing to act on a modified buffer (legu reads the file on disk)")))))

(defun legu--target-region (arg)
  "The (START . END) lines ARG asks for, or nil for the whole file.
ARG may also be an explicit (START . END) cons, which is how the queue
and the diff buffer name a region without faking a selection."
  (cond
   ((equal arg '(4)) nil)
   ((and (consp arg) (numberp (car arg)) (numberp (cdr arg)))
    (let ((total (legu--buffer-lines)))
      (unless (and (<= 1 (car arg)) (<= (car arg) (cdr arg)) (<= (cdr arg) total))
        (user-error "legu: %d-%d is outside %s (1-%d)"
                    (car arg) (cdr arg) (or legu--relpath (buffer-name)) total))
      arg))
   ((equal arg '(16))
    (let* ((dwim (legu--target-region nil))
           (default (and dwim (format "%d-%d" (car dwim) (cdr dwim))))
           (s (read-string (format "Range%s: " (if default (format " (%s)" default) ""))
                           nil nil default)))
      (if (string-match "\\`\\([0-9]+\\)-\\([0-9]+\\)\\'" s)
          (cons (string-to-number (match-string 1 s))
                (string-to-number (match-string 2 s)))
        (user-error "legu: not a line range: %s" s))))
   ((legu--selection-p)
    (let* ((visual (legu--visual-region))
           (beg (if visual (car visual) (region-beginning)))
           (end (if visual (cdr visual) (region-end)))
           (total (legu--buffer-lines))
           (start-line (min (legu--line-number beg) (max 1 total)))
           (end-line
            (if visual
                ;; evil's end is exclusive: the last character selected is
                ;; the one before it.
                (legu--line-number (max beg (1- end)))
              (let ((line (legu--line-number end)))
                ;; A region ending at column 0 does not include that line.
                (if (and (> line start-line) (= end (legu--line-position line)))
                    (1- line)
                  line)))))
      (cons start-line (min (max end-line start-line) (max 1 total)))))
   (t
    (let* ((total (max 1 (legu--buffer-lines)))
           (here (min (legu--line-number) total))
           (frontier (min (if (and legu--frontier (marker-position legu--frontier))
                              (legu--line-number legu--frontier)
                            1)
                          total)))
      (when (< here frontier)
        (user-error
         "legu: point is above the reading frontier; select a region or press %s"
         (key-description (kbd "C-c r SPC"))))
      (cons frontier here)))))

(defun legu--target-string (relpath region)
  "The positional argument legu wants for RELPATH and REGION."
  (if region (format "%s:%d-%d" relpath (car region) (cdr region)) relpath))

;;;###autoload
(defun legu-mark (&optional arg)
  "Mark a region of this file read.

With no active region, marks from the reading frontier down to point --
everything you have just read.  With a region, marks that region.  With
\\[universal-argument], the whole file; with two, prompts for a range."
  (interactive "P")
  (legu--assert-usable)
  ;; Save first: a `before-save-hook' formatter moves the very lines we are
  ;; about to name, and legu records what ends up on disk.  If the save moved
  ;; them, neither measurement is the region the user meant, so say so rather
  ;; than record the wrong one -- a reformat that collapses the mark would
  ;; otherwise silently widen a two-line mark to the whole file.
  (let ((before (and (buffer-modified-p) (ignore-errors (legu--target-region arg)))))
    (legu--ensure-saved)
    (let ((after (legu--target-region arg)))
      (when (and before (not (equal before after)))
        (user-error "legu: saving moved the region (%d-%d became %d-%d); select it again"
                    (car before) (cdr before) (car after) (cdr after)))))
  (let* ((region (legu--target-region arg))
         (span (and region (1+ (- (cdr region) (car region))))))
    (when (and span (not (legu--selection-p)) (not (equal arg '(16)))
               (> span legu-frontier-max)
               (not (y-or-n-p (format "Mark %d lines (%d-%d) read? "
                                      span (car region) (cdr region)))))
      (user-error "legu: cancelled"))
    (let* ((root legu--root)
           (rel legu--relpath)
           (buffer (current-buffer))
           (target (legu--target-string rel region))
           (lines (legu--buffer-lines))
           (added (cond (region (list (cons (car region) (cdr region))))
                        ((> lines 0) (list (cons 1 lines)))))
           (old-frontier (and legu--frontier (marker-position legu--frontier))))
      (setq legu--unverified t)
      (legu--repaint)
      (when added
        (setq legu--frontier
              (copy-marker (legu--line-position
                            (min (max 1 lines) (1+ (cdr (car (last added))))))
                           t)))
      (message "marked %s" target)
      (when (and span (> span legu-large-region-lines) (not legu--nudged))
        (setq legu--nudged t)
        (message "legu: mark regions you can hold in your head — a whole region goes stale when any line in it changes"))
      (legu--enqueue-write
       root (append (list "mark" target)
                    (when legu-reviewer (list "--reviewer" legu-reviewer)))
       (lambda (status _stdout stderr)
         (if (eq status 'ok)
             (progn
               (legu--patch-snapshot root rel :reviewed added)
               (unless (string-empty-p (string-trim stderr))
                 (legu--warn-once (list 'mark rel) stderr))
               (when (buffer-live-p buffer)
                 (with-current-buffer buffer
                   ;; Only the save that preceded this mark clears the alarm.
                   ;; If the user typed while the write was in flight, what is
                   ;; on screen is not what legu just read.
                   (setq legu--unverified (buffer-modified-p))
                   (legu--repaint)
                   (run-hooks 'legu-after-mark-hook))))
           (legu--record-failure root "mark" target stderr)
           (message "%s" (propertize (string-trim stderr) 'face 'warning))
           (when (buffer-live-p buffer)
             (with-current-buffer buffer
               (setq legu--unverified (buffer-modified-p))
               (when old-frontier (setq legu--frontier (copy-marker old-frontier t)))
               (legu--repaint)))))))))

(defun legu-mark-file ()
  "Mark this whole file read."
  (interactive)
  (legu-mark '(4)))

(defun legu-set-frontier ()
  "Set the reading frontier to point."
  (interactive)
  (setq legu--frontier (copy-marker (line-beginning-position) t))
  (legu--repaint)
  (message "legu: frontier at line %d" (legu--line-number)))

(defun legu-ticket (ticket &optional arg)
  "Anchor TICKET, an id in an external tracker, to the region at point.
legu stores the anchor; the ticket itself lives in the tracker."
  (interactive
   (list (completing-read
          (format "Ticket for %s: "
                  (legu--target-string
                   (or legu--relpath (buffer-name))
                   (ignore-errors (legu--target-region current-prefix-arg))))
          (funcall legu-ticket-completion-function)
          nil nil)
         current-prefix-arg))
  (legu--assert-usable)
  (when (string-empty-p (string-trim ticket))
    (user-error "legu: ticket needs a ticket id"))
  (legu--ensure-saved)
  (let* ((root legu--root)
         (rel legu--relpath)
         (buffer (current-buffer))
         (target (legu--target-string rel (legu--target-region arg))))
    (legu--enqueue-write
     root (list "ticket" target ticket)
     (lambda (status _stdout stderr)
       (if (eq status 'ok)
           (progn (message "anchored %s at %s" ticket target)
                  (when (buffer-live-p buffer)
                    (with-current-buffer buffer (legu--repaint))))
         (legu--record-failure root "ticket" (format "%s %s" target ticket) stderr)
         (message "%s" (propertize (string-trim stderr) 'face 'warning)))))))

(defun legu-forget (&optional arg)
  "Drop the review state of the region at point.
The record is recoverable from git: `.review/' is committed."
  (interactive "P")
  (legu--assert-usable)
  (let* ((root legu--root)
         (rel legu--relpath)
         (region (legu--target-region arg))
         (target (legu--target-string rel region)))
    (unless (yes-or-no-p
             (format "Forget review state at %s?  (recoverable from git) " target))
      (user-error "legu: cancelled"))
    (let ((buffer (current-buffer)))
      (legu--enqueue-write
       root (list "forget" target)
       (lambda (status stdout stderr)
         (if (eq status 'ok)
             (progn
               (message "%s" (string-trim stdout))
               (legu--patch-snapshot root rel :unreviewed
                                     (and region (list (cons (car region) (cdr region)))))
               (when (buffer-live-p buffer)
                 (with-current-buffer buffer (legu--repaint))))
           (legu--record-failure root "forget" target stderr)
           (message "%s" (propertize (string-trim stderr) 'face 'warning))))))))

(defun legu--gaps ()
  "Ranges of this buffer that are unread or stale."
  (let* ((state legu--painted)
         (total (or (plist-get state :total) (legu--buffer-lines))))
    (legu--ranges-union
     (legu--ranges-complement
      (legu--ranges-union (plist-get state :reviewed) (plist-get state :stale))
      total)
     (plist-get state :stale))))

(defun legu--goto-range (ranges forward what)
  "Move point to the next range in RANGES, in direction FORWARD.
WHAT names the thing for the error message."
  (let* ((here (legu--line-number))
         (starts (mapcar #'car ranges))
         (target (if forward
                     (seq-find (lambda (l) (> l here)) starts)
                   (car (last (seq-filter (lambda (l) (< l here)) starts))))))
    (if (not target)
        (message "legu: no %s %s here" (if forward "further" "previous") what)
      (let ((pos (legu--line-position target)))
        ;; The target may be outside a narrowed region; goto-char would
        ;; silently clamp and leave point somewhere else entirely.
        (unless (and (>= pos (point-min)) (<= pos (point-max))) (widen))
        (goto-char pos))
      (message "legu: line %d" target))))

(defun legu-next-gap ()
  "Move to the next unread or stale line in this buffer."
  (interactive)
  (legu--goto-range (legu--gaps) t "gap"))

(defun legu-previous-gap ()
  "Move to the previous unread or stale line in this buffer."
  (interactive)
  (legu--goto-range (legu--gaps) nil "gap"))

(defun legu-next-stale ()
  "Move to the next stale region in this buffer."
  (interactive)
  (legu--goto-range (plist-get legu--painted :stale) t "stale region"))

(defun legu-previous-stale ()
  "Move to the previous stale region in this buffer."
  (interactive)
  (legu--goto-range (plist-get legu--painted :stale) nil "stale region"))

(defun legu-next-file ()
  "Visit the first file in the reading queue, at its first gap."
  (interactive)
  (let* ((root (or legu--root (legu-root)))
         (queue (plist-get (legu-snapshot root) :queue)))
    (if (null queue)
        (message "legu: nothing queued (no snapshot yet?  %s)"
                 (key-description (kbd "C-u C-c r g")))
      (let* ((row (car queue))
             (ranges (plist-get row :ranges)))
        (find-file (expand-file-name (plist-get row :path) root))
        (when ranges (goto-char (legu--line-position (car (car ranges)))))))))

(defun legu--current-anchor-covers-p (anchor line)
  "Return non-nil when current ANCHOR covers LINE.
Opaque anchors cover their whole file."
  (let ((start (alist-get 'start anchor)) (end (alist-get 'end anchor)))
    (or (and (null start) (null end) (alist-get 'opaque anchor))
        (and start end (<= start line) (<= line end)))))

(defun legu--describe-anchor (path anchor)
  "Return the provenance of current ANCHOR in PATH."
  (let* ((original (alist-get 'original anchor))
         (commit (or (alist-get 'commit original) "?"))
         (current (if (alist-get 'start anchor)
                      (format "%s:%s-%s" path
                              (alist-get 'start anchor) (alist-get 'end anchor))
                    path))
         (recorded (if (alist-get 'start original)
                       (format "%s:%s-%s" (alist-get 'path original)
                               (alist-get 'start original) (alist-get 'end original))
                     (or (alist-get 'path original) path))))
    (format "%s %s%s; recorded %s, reviewed at %s by %s, commit %s"
            current
            (or (alist-get 'state anchor) "unknown")
            (if-let* ((reason (alist-get 'reason anchor)))
                (format " (%s)" reason)
              "")
            recorded
            (or (alist-get 'timestamp original) "?")
            (or (alist-get 'reviewer original) "?")
            (substring commit 0 (min 8 (length commit))))))

(defun legu--describe-regions-answer (line answer)
  "Render a parsed regions ANSWER for LINE into one echo-area string."
  (let* ((path (alist-get 'path answer))
         (records (seq-filter (lambda (r) (legu--current-anchor-covers-p r line))
                              (alist-get 'regions answer)))
         (tickets (seq-filter (lambda (r) (legu--current-anchor-covers-p r line))
                              (alist-get 'tickets answer)))
         (parts (mapcar (lambda (r) (legu--describe-anchor path r)) records))
         (ticket-ids (mapcar (lambda (r) (alist-get 'ticket r)) tickets)))
    (unless parts
      (setq parts (list (format "%s:%d unreviewed" path line))))
    (when ticket-ids
      (setq parts (append parts
                          (list (format "tickets [%s]"
                                        (mapconcat #'identity ticket-ids " "))))))
    (unless (alist-get 'complete answer)
      (setq parts (append parts (list "review state incomplete"))))
    (concat "legu: " (string-join parts "\n"))))

(defun legu-describe-region ()
  "Query and echo current anchors, provenance and tickets at point."
  (interactive)
  (unless (and legu--root legu--relpath buffer-file-name)
    (user-error "legu: not visiting a file in a legu repository"))
  (when (buffer-modified-p)
    (user-error "legu: save the buffer before describing its review state"))
  (let* ((buffer (current-buffer))
         (root legu--root)
         (path legu--relpath)
         (line (legu--line-number))
         (tick (buffer-chars-modified-tick))
         (request (setq legu--regions-request (1+ legu--regions-request))))
    (legu--run
     root (list "regions" path "--json")
     (lambda (status stdout stderr)
       (when (and (buffer-live-p buffer)
                  (with-current-buffer buffer
                    (and (= request legu--regions-request)
                         (= tick (buffer-chars-modified-tick)))))
         (if (eq status 'ok)
             (if-let* ((answer (legu--parse-json stdout)))
                 (message "%s" (legu--describe-regions-answer line answer))
               (message "legu: invalid regions response"))
           (message "%s" (string-trim stderr))))))))

(defun legu-visit-ticket ()
  "Visit the ticket anchored at point."
  (interactive)
  (let* ((line (legu--line-number))
         (tickets (legu-tickets-at legu--root legu--relpath line)))
    (if (null tickets)
        (message "legu: no ticket on this region")
      (funcall legu-ticket-visit-function
               (if (cdr tickets) (completing-read "Ticket: " tickets nil t) (car tickets))))))

(defun legu-visit-ticket-default (ticket)
  "Show TICKET with the knot ticket tracker, if it is installed."
  (if (executable-find "knot")
      (compilation-start (format "knot show %s" (shell-quote-argument ticket))
                         nil (lambda (&rest _) (format "*ticket %s*" ticket)))
    (user-error "legu: set `legu-ticket-visit-function' to open %s" ticket)))

;;;###autoload
(defun legu-coverage (&optional refresh)
  "Report the three coverage numbers in the echo area.
With a prefix argument REFRESH, refresh the snapshot first."
  (interactive "P")
  (let ((root (or legu--root (legu-root))))
    (unless root (user-error "legu: not in a legu repository"))
    (if refresh
        (let ((buffer (current-buffer)))
          (message "legu: refreshing…")
          ;; Registered before the request, so `want' is the generation we are
          ;; waiting to leave behind rather than the one already in flight.
          (legu--after-refresh
           root (lambda ()
                  (when (buffer-live-p buffer)
                    (with-current-buffer buffer (legu-coverage nil)))))
          (legu-refresh-snapshot root))
      (let* ((snapshot (legu-snapshot root))
             (cov (plist-get snapshot :coverage)))
        (if (null cov)
            (message "legu: no snapshot yet; %s to take one"
                     (key-description (kbd "C-u C-c r c")))
          (let ((lines (max 1 (plist-get cov :lines))))
            (message "legu: %d eligible lines · %.1f%% read · %.1f%% stale · %.1f%% never read  (%s)"
                     (plist-get cov :lines)
                     (* 100.0 (/ (float (plist-get cov :reviewed)) lines))
                     (* 100.0 (/ (float (plist-get cov :stale)) lines))
                     (* 100.0 (/ (float (plist-get cov :never)) lines))
                     (legu-snapshot-age-string snapshot))))))))

(defun legu-snapshot-age-string (snapshot)
  "Human age of SNAPSHOT."
  (let ((started (plist-get snapshot :started)))
    (cond
     ((eq (plist-get snapshot :state) 'refreshing) "refreshing…")
     ((null started) "no snapshot")
     (t (let ((age (float-time (time-subtract (current-time) started))))
          (cond ((< age 90) (format "snapshot %ds ago" (round age)))
                ((< age 5400) (format "snapshot %dm ago" (round (/ age 60))))
                (t (format "snapshot %dh ago" (round (/ age 3600))))))))))

(defun legu--after-refresh (root fn)
  "Call FN once ROOT's in-flight refresh lands, or give up after a while."
  (let ((want (or (gethash root legu--generations) 0))
        (deadline (time-add (current-time) 60))
        (timer nil))
    (setq timer
          (run-with-timer
           0.2 0.2
           (lambda ()
             (let* ((snapshot (legu-snapshot root))
                    (gen (plist-get snapshot :generation)))
               (cond
                ((and (not (eq (plist-get snapshot :state) 'refreshing))
                      gen (> gen want))
                 (cancel-timer timer)
                 (funcall fn))
                ((eq (plist-get snapshot :state) 'error)
                 (cancel-timer timer))
                ((time-less-p deadline (current-time))
                 (cancel-timer timer)
                 (message "legu: refresh timed out")))))))))

(defun legu-refresh (&optional force)
  "Repaint this buffer from disk.  With FORCE, refresh the snapshot too."
  (interactive "P")
  (clrhash legu--root-cheap-cache)
  (when force
    (setq legu--schema-warned nil legu--warned-paths nil
          legu--version-checked nil)
    (let ((root (or legu--root (legu-root))))
      (when root
        (legu--snapshot-put root :state 'fresh)
        (legu--snapshot-put root :error nil)
        (legu--snapshot-put root :errors nil)
        (legu-refresh-snapshot root))))
  (legu--repaint)
  (when force (message "legu: refreshing…")))

(defun legu-toggle-highlights (&optional all)
  "Hide or show legu's indicators in this buffer, or with ALL, everywhere."
  (interactive "P")
  (if all
      (let ((hide (not legu--hidden)))
        (dolist (buf (buffer-list))
          (with-current-buffer buf
            (when legu-mode (setq legu--hidden hide) (legu--repaint)))))
    (setq legu--hidden (not legu--hidden))
    (legu--repaint)))

(defun legu-visit-sidecar (file &optional other-window)
  "Open the unreadable sidecar FILE, in smerge-mode if it is unmerged."
  (if other-window (find-file-other-window file) (find-file file))
  (when (save-excursion
          (goto-char (point-min))
          (re-search-forward "^<<<<<<< " nil t))
    (require 'smerge-mode)
    (smerge-mode 1)))

(defun legu-visit-broken-store ()
  "Open the first sidecar legu could not read."
  (interactive)
  (let* ((root (or legu--root (legu-root)))
         (file (plist-get (car (plist-get (legu-snapshot root) :errors)) :file)))
    (if (not file)
        (message "legu: no store error recorded")
      (legu-visit-sidecar (expand-file-name file root)))))


;;;; The failures buffer

(defvar-keymap legu-failures-mode-map
  :parent special-mode-map
  "r" #'legu-failures-retry
  "RET" #'legu-failures-visit
  "k" #'legu-failures-discard
  "K" #'legu-failures-discard-all
  "g" #'revert-buffer)

(define-derived-mode legu-failures-mode special-mode "legu-failures"
  "Mutations legu refused, so an async miss is never a silently lost mark."
  (setq-local revert-buffer-function (lambda (&rest _) (legu-list-failures))))

;;;###autoload
(defun legu-list-failures ()
  "Show the mutations legu refused."
  (interactive)
  (let ((buffer (get-buffer-create "*legu-failures*")))
    (with-current-buffer buffer
      (legu-failures-mode)
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (propertize (format "Failed legu writes (%d)\n\n" (length legu--failures))
                            'face 'bold))
        (if (null legu--failures)
            (insert "  none\n")
          (dolist (f legu--failures)
            (let ((start (point)))
              (insert (format "  %s  %s %s\n            %s\n"
                              (plist-get f :time) (plist-get f :verb)
                              (plist-get f :args)
                              (propertize (plist-get f :message) 'face 'legu-error)))
              (insert "            [r] retry   [RET] visit   [k] discard\n\n")
              (put-text-property start (point) 'legu-failure f))))
        (goto-char (point-min))))
    (pop-to-buffer buffer)))

(defun legu-failures-retry ()
  "Retry the failed mutation at point."
  (interactive)
  (let ((f (get-text-property (point) 'legu-failure)))
    (unless f (user-error "legu: no failure at point"))
    (setq legu--failures (delq f legu--failures))
    (legu--enqueue-write
     (plist-get f :root)
     (cons (plist-get f :verb) (split-string (plist-get f :args) " " t))
     (lambda (status _stdout stderr)
       (if (eq status 'ok) (message "legu: retried %s" (plist-get f :args))
         (legu--record-failure (plist-get f :root) (plist-get f :verb)
                               (plist-get f :args) stderr)
         (message "%s" (string-trim stderr)))
       (legu-list-failures)))
    (legu-list-failures)))

(defun legu-failures-visit ()
  "Visit the file the failed mutation at point names."
  (interactive)
  (let ((f (get-text-property (point) 'legu-failure)))
    (unless f (user-error "legu: no failure at point"))
    (let* ((args (plist-get f :args))
           (path (car (split-string args " " t)))
           (path (car (split-string path ":"))))
      (find-file (expand-file-name path (plist-get f :root))))))

(defun legu-failures-discard ()
  "Discard the failure at point."
  (interactive)
  (let ((f (get-text-property (point) 'legu-failure)))
    (unless f (user-error "legu: no failure at point"))
    (setq legu--failures (delq f legu--failures))
    (legu-list-failures)))

(defun legu-failures-discard-all ()
  "Discard every recorded failure."
  (interactive)
  (setq legu--failures nil)
  (legu-list-failures))


;;;; Keymap

(defvar-keymap legu-command-map
  :doc "Keymap for legu commands, bound under `legu-prefix-key'."
  "r" #'legu-mark
  "R" #'legu-mark-file
  "SPC" #'legu-set-frontier
  "n" #'legu-next-gap
  "p" #'legu-previous-gap
  "]" #'legu-next-stale
  "[" #'legu-previous-stale
  "s" #'legu-diff-stale
  "." #'legu-describe-region
  "t" #'legu-ticket
  "T" #'legu-visit-ticket
  "k" #'legu-forget
  "l" #'legu-list
  "J" #'legu-next-file
  "c" #'legu-coverage
  "g" #'legu-refresh
  "h" #'legu-toggle-highlights
  "f" #'legu-list-failures
  "?" #'legu-dispatch)

(defvar legu-mode-map (make-sparse-keymap)
  "Keymap active in buffers where `legu-mode' is on.")

(defun legu--install-prefix (key)
  "Bind `legu-command-map' under KEY in `legu-mode-map'.
The keymap object itself is never replaced: `define-minor-mode' has
already registered it in `minor-mode-map-alist' by identity."
  (setcdr legu-mode-map nil)
  (when key (keymap-set legu-mode-map key legu-command-map)))

(defcustom legu-prefix-key "C-c r"
  "Prefix key for `legu-command-map' inside `legu-mode' buffers."
  :type 'key
  :set (lambda (sym value)
         (set-default sym value)
         (legu--install-prefix value))
  :group 'legu)

(legu--install-prefix legu-prefix-key)

(defvar-keymap legu-repeat-map
  :doc "Repeatable reading loop: C-c r r, then n r n r."
  :repeat t
  "r" #'legu-mark
  "n" #'legu-next-gap
  "p" #'legu-previous-gap
  "]" #'legu-next-stale
  "[" #'legu-previous-stale
  "s" #'legu-diff-stale
  "." #'legu-describe-region
  "SPC" #'legu-set-frontier)


;;;; The mode

(defun legu--first-change ()
  "Dim the indicators: every legu answer now describes a file on disk.
No process runs and nothing repaints from the snapshot -- the file the
CLI can see is no longer the file on screen."
  (setq legu--unverified t)
  (legu-overlay-dim)
  (force-mode-line-update))

(defun legu--after-save ()
  "Re-derive state from the saved file and ask for a fresh snapshot."
  (setq legu--unverified nil)
  (legu--repaint)
  (legu--file-regions-maybe-query)
  (when legu--unaccounted
    (legu-refresh-snapshot legu--root (legu--snapshot-debounce legu--root))))

(defun legu--after-revert ()
  "Tear down and repaint after the buffer was reverted."
  (legu-overlay-clear)
  (setq legu--frontier nil legu--unverified nil)
  (legu--repaint)
  (legu--file-regions-maybe-query))

(defun legu--window-change (_frame)
  "Repaint if the buffer moved between a graphical frame and a terminal."
  (dolist (buf (buffer-list))
    (with-current-buffer buf
      (when (and legu-mode (legu-overlay-style-changed-p))
        (legu--repaint)))))

(defun legu--watch-store (root)
  "Watch ROOT's .review tree, so other people's marks show up.
File notification is not recursive, and the store mirrors the source
tree, so every directory in it needs its own watch -- and new ones have
to be picked up as they are created."
  (when (and legu-watch-store
             (file-directory-p (expand-file-name ".review" root)))
    (let* ((store (expand-file-name ".review" root))
           (watched (gethash root legu--watchers))
           (dirs (cons store
                       (seq-filter #'file-directory-p
                                   (directory-files-recursively
                                    store "" t nil t)))))
      (dolist (dir dirs)
        (let ((entry (assoc dir watched)))
          ;; A watch on a directory that was deleted and recreated is dead but
          ;; still present; trusting the entry would leave it unwatched forever.
          (when (and entry (not (file-notify-valid-p (cdr entry))))
            (ignore-errors (file-notify-rm-watch (cdr entry)))
            (setq watched (delq entry watched) entry nil))
          (unless entry
            (condition-case nil
                (push (cons dir
                            (file-notify-add-watch
                             dir '(change)
                             (lambda (event)
                               ;; A new sidecar directory announces itself on
                               ;; its watched parent.  Re-arming on every write
                               ;; instead would rescan the whole store once per
                               ;; sidecar a pull rewrites.
                               (when (and (memq (nth 1 event) '(created renamed))
                                          (file-directory-p (nth 2 event)))
                                 (legu--watch-store root))
                               (legu-refresh-snapshot
                                root (legu--snapshot-debounce root)))))
                      watched)
              (error nil)))))
      (puthash root watched legu--watchers))))

(defun legu--buffer-in-root-p (buf root)
  "Whether BUF shows ROOT under `legu-mode' or `legu-dired-mode'."
  (and (equal (buffer-local-value 'legu--root buf) root)
       (or (buffer-local-value 'legu-mode buf)
           (and (boundp 'legu-dired-mode)
                (buffer-local-value 'legu-dired-mode buf)))
       t))

(defun legu--unwatch-maybe (root)
  "Drop ROOT's watchers once no legu buffer is left in it.
The buffer being killed is still in `buffer-list' with the mode on, so
it does not count."
  (unless (seq-some (lambda (buf)
                      (and (not (eq buf (current-buffer)))
                           (legu--buffer-in-root-p buf root)))
                    (buffer-list))
    (dolist (entry (gethash root legu--watchers))
      (ignore-errors (file-notify-rm-watch (cdr entry))))
    (remhash root legu--watchers)))

(defvar legu--seen-roots nil
  "Roots that have had a snapshot requested this session.")

(defun legu--first-visit (root)
  "Ask for ROOT's first snapshot, once per session, after a short idle."
  (unless (member root legu--seen-roots)
    (push root legu--seen-roots)
    (run-with-idle-timer legu-snapshot-initial-delay nil
                         #'legu-refresh-snapshot root)))

;;;###autoload
(define-minor-mode legu-mode
  "Show which lines of this file have been read, and which have gone stale.

\\{legu-mode-map}"
  :lighter legu-lighter
  :keymap legu-mode-map
  (if legu-mode
      (let ((root (legu-root buffer-file-name)))
        (cond
         ((null buffer-file-name)
          (setq legu-mode nil)
          (user-error "legu: this buffer is not visiting a file"))
         ((file-remote-p buffer-file-name)
          (setq legu-mode nil)
          (user-error "legu: remote files are not supported"))
         ((null root)
          (setq legu-mode nil)
          (user-error "legu: not in a git repository or a .review store"))
         (t
          (setq legu--root root
                legu--relpath (legu--relative root buffer-file-name)
                legu--frontier nil
                legu--unverified (buffer-modified-p))
          (add-hook 'first-change-hook #'legu--first-change nil t)
          (add-hook 'after-save-hook #'legu--after-save nil t)
          (add-hook 'after-revert-hook #'legu--after-revert nil t)
          (add-hook 'kill-buffer-hook #'legu--teardown nil t)
          (add-hook 'window-buffer-change-functions #'legu--window-change)
          (legu--watch-store root)
          (legu--repaint)
          (legu--file-regions-maybe-query)
          (when legu--unaccounted
            (legu-refresh-snapshot root (legu--snapshot-debounce root)))
          (legu--first-visit root))))
    (legu--teardown)))

(defun legu--teardown ()
  "Remove this buffer's overlays and hooks, and the repository's if it is the last."
  (legu-overlay-clear)
  (setq legu--content-seen nil legu--file-regions nil)
  (remove-hook 'first-change-hook #'legu--first-change t)
  (remove-hook 'after-save-hook #'legu--after-save t)
  (remove-hook 'after-revert-hook #'legu--after-revert t)
  (remove-hook 'kill-buffer-hook #'legu--teardown t)
  (when legu--root (legu--unwatch-maybe legu--root))
  (unless (seq-some (lambda (buf)
                      (and (not (eq buf (current-buffer)))
                           (buffer-local-value 'legu-mode buf)))
                    (buffer-list))
    (remove-hook 'window-buffer-change-functions #'legu--window-change)))

(defun legu--turn-on-maybe ()
  "Turn `legu-mode' on where it can do something useful, and nowhere else.
A dired buffer under a store gets `legu-dired-mode' instead."
  (cond
   ((derived-mode-p 'dired-mode)
    ;; The cheap gates first, so a dired buffer outside any store never
    ;; loads legu-dired.
    (when (and legu-dired-column
               (not (file-remote-p default-directory))
               (legu--root-cheap default-directory)
               (legu-dired-eligible-p))
      (legu-dired-mode 1)))
   ((and buffer-file-name
         (not (file-remote-p buffer-file-name))
         (not (apply #'derived-mode-p legu-exclude-modes))
         (let ((a (file-attributes buffer-file-name)))
           (and a (< (file-attribute-size a) legu-max-file-size)))
         (legu--root-cheap default-directory))
    (legu-mode 1))))

;;;###autoload
(define-globalized-minor-mode global-legu-mode legu-mode legu--turn-on-maybe
  :group 'legu)

(defun legu--global-mode-off ()
  "Turn the dired column off everywhere when `global-legu-mode' goes off.
The globalized mode only knows how to turn `legu-mode' off."
  (unless global-legu-mode
    (dolist (buf (buffer-list))
      (when (and (boundp 'legu-dired-mode) (buffer-local-value 'legu-dired-mode buf))
        (with-current-buffer buf (legu-dired-mode -1))))))

(add-hook 'global-legu-mode-hook #'legu--global-mode-off)

(provide 'legu)

;; After the `provide' above, because this body runs immediately when evil is
;; already loaded, and legu-evil requires the rest of the package back.
(with-eval-after-load 'evil
  (when legu-evil-integration (require 'legu-evil)))

;;; legu.el ends here
