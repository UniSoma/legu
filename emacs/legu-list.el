;;; legu-list.el --- The legu reading queue  -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Jonas Rodrigues
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; One buffer per repository, built entirely from the cached snapshot: `g'
;; is the only thing that shells out.  It derives from `compilation-mode'
;; so `M-g M-n' steps through review gaps from anywhere in Emacs, which is
;; the whole reason every content row starts with `path:start:end:'.
;;
;; The three coverage numbers live here, as three labelled rows, always
;; visible.  Never one number.

;;; Code:

(require 'compile)
(require 'legu)

(defvar-local legu-list--root nil)
(defvar-local legu-list--scope nil
  "Non-nil to show only this path.")
(defvar-local legu-list--filter nil)

(defvar legu-list--record-cache nil
  "Sidecar records read during one render, keyed by path.")

(defcustom legu-list-filter 'all
  "Which rows the queue buffer shows by default."
  :type '(choice (const all) (const stale) (const unread))
  :group 'legu)

(defvar-keymap legu-list-mode-map
  :parent compilation-mode-map
  "RET" #'legu-list-visit
  "o" #'legu-list-visit-other-window
  "r" #'legu-list-mark
  "s" #'legu-list-diff
  "t" #'legu-list-ticket
  "k" #'legu-list-forget
  "f" #'legu-list-toggle-filter
  "g" #'revert-buffer
  "c" #'legu-coverage
  "?" #'legu-dispatch)

(defconst legu-list--font-lock-keywords '((compilation--ensure-parse))
  "Only the parser.  The generic compilation rules would paint every row.")

(define-derived-mode legu-list-mode compilation-mode "legu"
  "The legu reading queue.

\\{legu-list-mode-map}"
  (setq-local compilation-error-regexp-alist
              '(("^\\([^ \t\n:][^\n:]*\\):\\([0-9]+\\):\\([0-9]+\\):" 1 2 nil 2)))
  (setq-local compilation-error-screen-columns nil)
  (setq-local next-error-function #'compilation-next-error-function)
  (setq-local revert-buffer-function #'legu-list--revert)
  (setq-local truncate-lines t)
  ;; The parser paints every `path:start:end:' it finds.  Give it this
  ;; buffer's faces so the anchor reads as a path, not as a compiler error.
  (setq-local font-lock-defaults '(legu-list--font-lock-keywords t))
  (setq-local compilation-message-face 'legu-list-anchor)
  (setq-local compilation-error-face 'legu-list-path)
  (setq-local compilation-line-face 'legu-list-anchor)
  (hl-line-mode 1))

(defun legu-list--buffer-name (root)
  "Name of ROOT's queue buffer.
Plain while one repository is in play; qualified once a second one is."
  (let ((plain (get-buffer "*legu*")))
    (if (or (null plain)
            (equal root (buffer-local-value 'legu-list--root plain)))
        "*legu*"
      (format "*legu: %s*"
              (file-name-nondirectory (directory-file-name root))))))

(defun legu-list--live-buffers ()
  "Every live queue buffer."
  (seq-filter (lambda (b) (with-current-buffer b (derived-mode-p 'legu-list-mode)))
              (buffer-list)))

;;;###autoload
(defun legu-list (&optional this-file)
  "Show the reading queue for this repository.
With a prefix argument THIS-FILE, scope it to the current file."
  (interactive "P")
  (let* ((root (or legu--root (legu-root)))
         (scope (and this-file buffer-file-name
                     (legu--relative root buffer-file-name))))
    (unless root (user-error "legu: not in a legu repository"))
    (let ((buffer (get-buffer-create (legu-list--buffer-name root))))
      (with-current-buffer buffer
        (unless (derived-mode-p 'legu-list-mode) (legu-list-mode))
        (setq legu-list--root root
              legu-list--scope scope
              legu-list--filter (or legu-list--filter legu-list-filter))
        (legu-list--render))
      (pop-to-buffer buffer)
      (unless (legu-snapshot root)
        (legu-refresh-snapshot root)))))

(defun legu-list-refresh-buffers (root)
  "Re-render every queue buffer showing ROOT."
  (dolist (buffer (legu-list--live-buffers))
    (with-current-buffer buffer
      (when (equal legu-list--root root)
        (legu-list--render)))))

(defun legu-list--revert (&rest _)
  "Force a fresh snapshot, then re-render."
  (let ((root legu-list--root))
    (legu-refresh-snapshot root)
    (legu-list--render)))

(defvar legu-list--anchor-width 46
  "Column the row text starts at, sized to the section being drawn.")

(defun legu-list--face (text face)
  "TEXT in FACE, whether or not font-lock is on.
`compilation-mode' fontifies, and fontification strips `face'; what it
leaves alone is `font-lock-face'."
  (propertize text 'face face 'font-lock-face face))

(defun legu-list--right (text)
  "A spacer that pushes TEXT to the window's right edge."
  (concat (propertize " " 'display `(space :align-to (- right ,(1+ (length text)))))
          text))

(defun legu-list--bar (fraction width face)
  "A bar FRACTION of WIDTH long, painted in FACE.
Anything too small for one cell still shows as a sliver, so a repository
with a few lines read does not look like one with none."
  (let ((n (round (* fraction width))))
    (legu-list--face (cond ((> n 0) (make-string n ?█))
                           ((> fraction 0) "▏")
                           (t ""))
                     face)))

(defun legu-list--percent (fraction)
  "FRACTION as a percentage that never rounds a few lines to nothing."
  (let ((pct (* 100 fraction)))
    (cond ((and (> pct 0) (< pct 0.05)) " <0.1%")
          ((and (< pct 100) (> pct 99.95)) ">99.9%")
          (t (format "%5.1f%%" pct)))))

(defun legu-list--render ()
  "Draw the queue from the cached snapshot.  Never shells out."
  (let* ((root legu-list--root)
         (snapshot (legu-snapshot root))
         (inhibit-read-only t)
         (line (line-number-at-pos (point)))
         (legu-list--record-cache (make-hash-table :test #'equal))
         (cov (plist-get snapshot :coverage)))
    (erase-buffer)
    (insert (legu-list--face
             (format "Review coverage — %s"
                     (file-name-nondirectory (directory-file-name root)))
             'legu-list-heading))
    (when legu-list--scope
      (insert (legu-list--face (format " · %s" legu-list--scope) 'legu-list-path)))
    (insert (legu-list--right
             (legu-list--face (legu-snapshot-age-string snapshot) 'legu-list-count))
            "\n")
    (when (or (eq (plist-get snapshot :state) 'error)
              (plist-get snapshot :errors))
      (legu-list--insert-error snapshot))
    (if (null cov)
        (insert "\n  " (legu-list--face "no snapshot yet — press g" 'legu-list-count) "\n")
      (legu-list--insert-coverage cov))
    (let ((stale (legu-list--insert-stale snapshot))
          (next (legu-list--insert-next snapshot)))
      (legu-list--insert-empty cov stale next))
    (insert "\n" (legu-list--face
                  (legu-list--keys '("RET" "visit") '("r" "mark") '("s" "diff")
                                   '("t" "ticket") '("k" "forget") '("f" "filter")
                                   '("g" "refresh") '("c" "coverage"))
                  'legu-list-count)
            "\n")
    (goto-char (point-min))
    (forward-line (1- line))))

(defun legu-list--keys (&rest pairs)
  "The footer: every (KEY LABEL) in PAIRS, keys picked out."
  (mapconcat (lambda (p)
               (concat (legu-list--face (car p) 'legu-list-key) " " (cadr p)))
             pairs "   "))

(defun legu-list--insert-empty (cov stale next)
  "Say what an empty queue means, given the section counts STALE and NEXT.
Silence would look like a broken render."
  (when (and cov (= 0 stale) (= 0 next))
    (insert "\n  "
            (legu-list--face
             (pcase legu-list--filter
               ('stale "no stale regions")
               ('unread "no unread files")
               (_ (if legu-list--scope
                      "this file is fully read"
                    "nothing to read — every eligible line is read")))
             'legu-list-count)
            "\n")))

(defun legu-list--insert-error (snapshot)
  "Insert SNAPSHOT's store error banner.
A snapshot with no numbers at all reports `:error' and says so.  One
that merely skipped sidecars names them: the numbers below it are live
and short by whatever those files hold."
  (let ((err (plist-get snapshot :error))
        (errors (plist-get snapshot :errors)))
    (cond
     (err
      (insert "\n" (legu-list--face "STORE ERROR — every legu command is failing"
                                    'legu-error)
              "\n")
      (insert (format "  %s\n" (plist-get err :message)))
      (when (plist-get snapshot :started)
        (insert (format "  Numbers below are from the last good snapshot, %s.\n"
                        (legu-snapshot-age-string snapshot)))))
     (errors
      (insert "\n"
              (legu-list--face
               (format "STORE ERROR — %d sidecar%s skipped; the numbers below leave %s out"
                       (length errors) (if (= 1 (length errors)) "" "s")
                       (if (= 1 (length errors)) "it" "them"))
               'legu-error)
              "\n")
      (dolist (e errors)
        (insert (propertize (format "  %s   %s\n" (plist-get e :file) (plist-get e :reason))
                            'legu-store-error
                            (expand-file-name (plist-get e :file) legu-list--root))))
      (insert "  RET visits the file (smerge-mode if it has conflict markers), then press g.\n")))))

(defun legu-list--insert-coverage (cov)
  "Insert the three numbers of COV, as three rows.  Never one number.
The bars share one scale, so the three rows read as one stacked bar."
  (let ((lines (max 1 (plist-get cov :lines)))
        (width (max 8 (min 40 (- (window-body-width (get-buffer-window)) 34)))))
    (insert "\n")
    (pcase-dolist (`(,label ,count ,face)
                   (list (list "never read" (plist-get cov :never) 'legu-list-never)
                         (list "read" (plist-get cov :reviewed) 'legu-reviewed)
                         (list "stale" (plist-get cov :stale) 'legu-stale)))
      (let ((fraction (/ (float count) lines)))
        (insert "  " (legu-list--face (format "%-12s" label) face)
                (format "%8d  " count)
                (legu-list--face (legu-list--percent fraction)
                                 (if (= count 0) 'legu-list-count 'default))
                "  " (legu-list--bar fraction width face) "\n")))
    (insert (legu-list--face
             (format "  %-12s %d files · %d lines" "eligible"
                     (plist-get cov :files) (plist-get cov :lines))
             'legu-list-count)
            (legu-list--right
             (concat (legu-list--face "f" 'legu-list-key) " "
                     (legu-list--face
                      (pcase legu-list--filter
                        ('stale "stale only") ('unread "unread only") (_ "all"))
                      'legu-list-count)))
            "\n")))

(defun legu-list--display-width (text)
  "How wide TEXT is on screen, counting an elided run as its ellipsis."
  (let ((i 0) (n (length text)) (width 0))
    (while (< i n)
      (let ((to (or (next-single-property-change i 'display text) n))
            (shown (get-text-property i 'display text)))
        (setq width (+ width (string-width (if (stringp shown)
                                               shown
                                             (substring text i to))))
              i to)))
    width))

(defun legu-list--suffix (text width)
  "The longest tail of TEXT no wider than WIDTH."
  (let ((i (length text)))
    (while (and (> i 0) (<= (string-width (substring text (1- i))) width))
      (setq i (1- i)))
    (substring text i)))

(defun legu-list--elide (path budget)
  "PATH, painted, with its middle hidden behind an ellipsis to fit BUDGET.
Only the display shrinks: the row still carries the whole path, because
that is what `next-error' parses and what tells two ticket slugs apart.
The tail gets the larger share, since files that share a directory are
told apart by their names."
  (let ((text (legu-list--face path 'legu-list-path)))
    (if (or (<= (string-width path) budget) (< budget 4))
        text
      (let* ((room (1- budget))
             (head (truncate-string-to-width path (/ room 3)))
             (tail (legu-list--suffix path (- room (string-width head))))
             (from (length head))
             (to (- (length path) (length tail))))
        (when (< from to)
          (put-text-property from to
                             'display (legu-list--face "…" 'legu-list-path)
                             text))
        text))))

(defun legu-list--row (path start end kind text)
  "Insert one navigable row.
The `path:start:end:' prefix is what `next-error' matches on; the text
properties are what this package itself reads, so a path containing a
colon still visits correctly."
  (let* ((from (point))
         (lines (format ":%s:%s:" (or start 1) (or end start 1)))
         (shown (legu-list--elide
                 path (- legu-list--anchor-width 2 (length lines)))))
    (insert shown
            (legu-list--face lines 'legu-list-anchor)
            (make-string (max 2 (- legu-list--anchor-width
                                   (+ (legu-list--display-width shown)
                                      (length lines))))
                         ?\s)
            text "\n")
    (put-text-property from (point) 'legu-path path)
    (put-text-property from (point) 'legu-start (or start 1))
    (put-text-property from (point) 'legu-end (or end start 1))
    (put-text-property from (point) 'legu-kind kind)))

(defun legu-list--anchor-width (anchors)
  "The column the row text starts at, given every anchor of a section.
Wide enough that the columns line up, never so wide that the counts to
the right of them fall off the window.  Anchors past it are elided."
  (let ((longest (apply #'max 0 (mapcar #'string-width anchors)))
        ;; Undisplayed buffers render too, and the first render of all
        ;; happens before the queue has a window: fall back to the cap
        ;; rather than to whatever window happens to be selected.
        (room (if-let* ((window (get-buffer-window)))
                  (- (window-body-width window) 34)
                72)))
    (max 36 (min 72 room (+ longest 3)))))

(defun legu-list--count (n unit &optional face)
  "N and UNIT as a count cell.  A zero is dimmed; N > 0 wears FACE."
  (legu-list--face (format "%5d %s" n unit)
                   (cond ((= n 0) 'legu-list-count) (face face) (t 'default))))

(defun legu-list--scoped-p (path)
  "Whether PATH passes this buffer's scope."
  (or (null legu-list--scope) (equal path legu-list--scope)))

(defun legu-list--record (path line)
  "The record of PATH covering LINE, reading each sidecar at most once."
  (let ((hit (gethash path legu-list--record-cache 'miss)))
    (when (eq hit 'miss)
      (setq hit (plist-get (legu-sidecar-records legu-list--root path) :regions))
      (puthash path hit legu-list--record-cache))
    (let ((best nil))
      (dolist (r hit)
        (let ((start (alist-get 'start r)) (end (alist-get 'end r)))
          (when (and start end (<= start line) (<= line end)
                     (or (null best)
                         (< (- end start)
                            (- (alist-get 'end best) (alist-get 'start best)))))
            (setq best r))))
      best)))

(defun legu-list--heading (name count unit &optional total)
  "Insert a section heading: NAME, then COUNT UNITs, of TOTAL when truncated."
  (insert "\n"
          (legu-list--face (format "%s  " name) 'legu-list-heading)
          (legu-list--face
           (format "%d%s %s%s" count
                   (if (and total (> total count)) (format " of %d" total) "")
                   unit (if (= 1 (or total count)) "" "s"))
           'legu-list-count)
          "\n"))

(defun legu-list--insert-stale (snapshot)
  "Insert SNAPSHOT's stale regions.  Returns how many rows were drawn."
  (let ((rows nil))
    (unless (eq legu-list--filter 'unread)
      (when-let* ((table (plist-get snapshot :stale)))
        (maphash (lambda (path entries)
                   (when (legu-list--scoped-p path)
                     (dolist (e entries) (push (cons path e) rows))))
                 table))
      (setq rows (sort rows (lambda (a b)
                              (if (equal (car a) (car b))
                                  (< (or (nth 0 (cdr a)) 0) (or (nth 0 (cdr b)) 0))
                                (string< (car a) (car b))))))
      (when rows
        (legu-list--heading "STALE" (length rows) "region")
        (let ((legu-list--anchor-width
               (legu-list--anchor-width
                (mapcar (lambda (row)
                          (format "%s:%s:%s:" (car row) (or (nth 0 (cdr row)) 1)
                                  (or (nth 1 (cdr row)) (nth 0 (cdr row)) 1)))
                        rows))))
          (dolist (row rows)
            (let* ((path (car row)) (e (cdr row))
                   (state (nth 3 e))
                   (record (legu-list--record path (or (nth 0 e) 1)))
                   (when-read (and record (alist-get 'timestamp record))))
              (legu-list--row
               path (nth 0 e) (nth 1 e) 'stale
               (concat
                (legu-list--face (format "%-8s" (or state "stale"))
                                 (if (equal state "missing") 'legu-missing 'legu-stale))
                (format " %-18s " (or (nth 2 e) ""))
                (legu-list--face
                 (if when-read (format "read %s" (substring when-read 0 10)) "")
                 'legu-list-count))))))))
    (length rows)))

(defun legu-list--insert-next (snapshot)
  "Insert SNAPSHOT's reading queue.  Returns how many rows were drawn."
  (let ((rows nil))
    (unless (eq legu-list--filter 'stale)
      (setq rows (seq-filter (lambda (r) (legu-list--scoped-p (plist-get r :path)))
                             (plist-get snapshot :queue)))
      (when rows
        (legu-list--heading "NEXT" (length rows) "file"
                            (and (not legu-list--scope)
                                 (legu-list--files-with-gaps snapshot)))
        (let ((legu-list--anchor-width
               (legu-list--anchor-width
                (mapcar (lambda (r)
                          (let ((ranges (plist-get r :ranges)))
                            (format "%s:%s:%s:" (plist-get r :path)
                                    (or (and ranges (car (car ranges))) 1)
                                    (or (and ranges (cdr (car ranges))) 1))))
                        rows))))
          (dolist (r rows)
            (let ((ranges (plist-get r :ranges)))
              (legu-list--row
               (plist-get r :path)
               (and ranges (car (car ranges)))
               (and ranges (cdr (car ranges)))
               'next
               (concat (legu-list--count (plist-get r :unreviewed) "unread")
                       " "
                       (legu-list--count (plist-get r :stale) "stale" 'legu-stale)
                       "   "
                       (legu-list--face (legu-format-ranges ranges) 'legu-list-count))))))))
    (length rows)))

(defun legu-list--files-with-gaps (snapshot)
  "How many files in SNAPSHOT still have unread or stale lines, or nil.
The queue shows at most `legu-next-limit' of them."
  (when-let* ((rows (plist-get snapshot :rows)))
    (let ((n 0))
      (maphash (lambda (_path row)
                 (when (> (+ (plist-get row :unreviewed) (plist-get row :stale)) 0)
                   (setq n (1+ n))))
               rows)
      n)))


;;;; Row actions

(defun legu-list--at-point ()
  "The row at point, as a plist, or nil."
  (when-let* ((path (get-text-property (point) 'legu-path)))
    (list :path path
          :start (get-text-property (point) 'legu-start)
          :end (get-text-property (point) 'legu-end)
          :kind (get-text-property (point) 'legu-kind))))

(defun legu-list--rows-in-region ()
  "Every row the active region touches, or the row at point."
  (if (not (legu--selection-p))
      (when-let* ((row (legu-list--at-point))) (list row))
    ;; The region end has to be read before point moves, and a row is a
    ;; duplicate of any row already collected, not merely of the last one.
    ;; Under evil the selection is what evil highlighted, not mark..point:
    ;; `V\=' on one row leaves those equal, and `Vj\=' stops one row short.
    (let* ((visual (legu--visual-region))
           (beg (if visual (car visual) (region-beginning)))
           ;; Both ends are exclusive here: a plain region that stops at the
           ;; start of a row does not select it, and evil's visual end is
           ;; exclusive by construction.
           (end (if visual (cdr visual) (region-end)))
           (rows nil))
      (save-excursion
        (goto-char beg)
        (while (< (point) end)
          (when-let* ((row (legu-list--at-point)))
            (unless (member row rows) (push row rows)))
          (forward-line 1)))
      (nreverse rows))))

(defun legu-list-visit (&optional other-window)
  "Visit the row at point, at its range start.
With OTHER-WINDOW, in another window."
  (interactive)
  (if-let* ((sidecar (get-text-property (point) 'legu-store-error)))
      (legu-visit-sidecar sidecar other-window)
    (let ((row (legu-list--at-point)))
      (unless row (user-error "legu: no row at point"))
      (let ((file (expand-file-name (plist-get row :path) legu-list--root)))
        (unless (file-exists-p file)
          (user-error "legu: %s no longer exists" (plist-get row :path)))
        (if other-window (find-file-other-window file) (find-file file))
        (goto-char (point-min))
        (forward-line (1- (or (plist-get row :start) 1)))))))

(defun legu-list-visit-other-window ()
  "Visit the row at point in another window."
  (interactive)
  (legu-list-visit t))

(defun legu-list--in-source (row fn)
  "Visit ROW's file in another window and call FN there."
  (let ((buffer (find-file-noselect
                 (expand-file-name (plist-get row :path) legu-list--root))))
    (with-current-buffer buffer
      (unless legu-mode (legu-mode 1))
      (goto-char (point-min))
      (forward-line (1- (or (plist-get row :start) 1)))
      (funcall fn row))))

(defun legu-list-mark ()
  "Mark the row at point read, or every row the region touches.
A stale row re-marks exactly its own range.  A queue row is a file with
unread lines in it, so recording it read is a claim about code nobody has
opened -- that one is always confirmed by name."
  (interactive)
  (let* ((rows (legu-list--rows-in-region))
         (whole (seq-remove (lambda (r) (eq (plist-get r :kind) 'stale)) rows)))
    (unless rows (user-error "legu: no row at point"))
    (cond
     (whole
      (unless (yes-or-no-p
               (format "Record %d file%s read in full, unopened (%s%s)%s? "
                       (length whole) (if (= 1 (length whole)) "" "s")
                       (mapconcat (lambda (r) (plist-get r :path))
                                  (seq-take whole 3) ", ")
                       (if (> (length whole) 3)
                           (format " and %d more" (- (length whole) 3))
                         "")
                       (let ((stale (- (length rows) (length whole))))
                         (if (> stale 0)
                             (format ", plus %d stale region%s"
                                     stale (if (= 1 stale) "" "s"))
                           ""))))
        (user-error "legu: cancelled")))
     ((> (length rows) 1)
      (unless (y-or-n-p (format "Re-mark %d stale regions read? " (length rows)))
        (user-error "legu: cancelled"))))
    (dolist (row rows)
      (legu-list--in-source
       row (lambda (r)
             (if (eq (plist-get r :kind) 'stale)
                 (legu-mark (cons (plist-get r :start) (plist-get r :end)))
               (legu-mark '(4))))))))

(defun legu-list-diff ()
  "Diff the stale region at point against the commit it was read at."
  (interactive)
  (let ((row (legu-list--at-point)))
    (unless row (user-error "legu: no row at point"))
    (legu-list--in-source row (lambda (_r) (legu-diff-stale)))))

(defun legu-list-ticket ()
  "Anchor a ticket to the region at point."
  (interactive)
  (let ((row (legu-list--at-point)))
    (unless row (user-error "legu: no row at point"))
    (legu-list--in-source
     row (lambda (r)
           (let ((region (cons (plist-get r :start) (plist-get r :end))))
             (legu-ticket (completing-read
                         (format "Ticket for %s:%d-%d: " (plist-get r :path)
                                 (car region) (cdr region))
                         (funcall legu-ticket-completion-function))
                        region))))))

(defun legu-list-forget ()
  "Drop the review state of the region at point."
  (interactive)
  (let ((row (legu-list--at-point)))
    (unless row (user-error "legu: no row at point"))
    (legu-list--in-source
     row (lambda (r)
           (legu-forget (if (eq (plist-get r :kind) 'stale)
                            (cons (plist-get r :start) (plist-get r :end))
                          '(4)))))))

(defun legu-list-toggle-filter ()
  "Cycle the queue filter: everything, stale only, unread only."
  (interactive)
  (setq legu-list--filter (pcase legu-list--filter
                            ('all 'stale) ('stale 'unread) (_ 'all)))
  (legu-list--render)
  (message "legu: showing %s" legu-list--filter))

(provide 'legu-list)
;;; legu-list.el ends here
