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

(define-derived-mode legu-list-mode compilation-mode "legu"
  "The legu reading queue.

\\{legu-list-mode-map}"
  (setq-local compilation-error-regexp-alist
              '(("^\\([^ \t\n:][^\n:]*\\):\\([0-9]+\\):\\([0-9]+\\):" 1 2 nil 2)))
  (setq-local compilation-error-screen-columns nil)
  (setq-local next-error-function #'compilation-next-error-function)
  (setq-local revert-buffer-function #'legu-list--revert)
  (setq-local truncate-lines t))

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

(defun legu-list--bar (fraction width)
  "A WIDTH character bar FRACTION full."
  (let ((n (round (* fraction width))))
    (concat (make-string n ?█) (make-string (max 0 (- width n)) ?░))))

(defun legu-list--render ()
  "Draw the queue from the cached snapshot.  Never shells out."
  (let* ((root legu-list--root)
         (snapshot (legu-snapshot root))
         (inhibit-read-only t)
         (line (line-number-at-pos (point)))
         (legu-list--record-cache (make-hash-table :test #'equal))
         (cov (plist-get snapshot :coverage)))
    (erase-buffer)
    (let ((heading (format "Review coverage — %s"
                           (file-name-nondirectory (directory-file-name root)))))
      (insert (propertize heading 'face 'legu-list-heading))
      (insert (propertize (format "%s%s\n"
                                  (make-string (max 2 (- 52 (length heading))) ?\s)
                                  (legu-snapshot-age-string snapshot))
                          'face 'legu-list-count)))
    (when (eq (plist-get snapshot :state) 'error)
      (legu-list--insert-error snapshot))
    (if (null cov)
        (insert "\n  no snapshot yet — press g\n")
      (legu-list--insert-coverage cov))
    (legu-list--insert-stale snapshot)
    (legu-list--insert-next snapshot)
    (insert "\n"
            (propertize
             "RET visit   r mark   s diff   t ticket   k forget   f filter   g refresh   c coverage\n"
             'face 'legu-list-count))
    (goto-char (point-min))
    (forward-line (1- line))))

(defun legu-list--insert-error (snapshot)
  "Insert SNAPSHOT's store error banner."
  (let* ((err (plist-get snapshot :error))
         (file (plist-get err :file)))
    (insert (propertize "\nSTORE ERROR — every legu command is failing\n"
                        'face 'legu-error))
    (insert (propertize (format "  %s   %s\n"
                                (if file (file-relative-name file legu-list--root) "store")
                                (plist-get err :message))
                        'legu-store-error file))
    (insert "  RET visits the file (smerge-mode if it has conflict markers), then press g.\n")
    (when (plist-get snapshot :started)
      (insert (format "  Numbers below are from the last good snapshot, %s.\n"
                      (legu-snapshot-age-string snapshot))))))

(defun legu-list--insert-coverage (cov)
  "Insert the three numbers of COV, as three rows.  Never one number."
  (let ((lines (max 1 (plist-get cov :lines))))
    (insert "\n")
    (dolist (row (list (list "never read" (plist-get cov :never))
                       (list "read" (plist-get cov :reviewed))
                       (list "stale" (plist-get cov :stale))))
      (let ((fraction (/ (float (nth 1 row)) lines)))
        (insert (format "  %-12s %8d  %5.1f%%  %s\n"
                        (nth 0 row) (nth 1 row) (* 100 fraction)
                        (legu-list--bar fraction 35)))))
    (insert (propertize (format "  %-12s %d files / %d lines\n"
                                "eligible" (plist-get cov :files) (plist-get cov :lines))
                        'face 'legu-list-count))))

(defun legu-list--row (path start end kind text)
  "Insert one navigable row.
The `path:start:end:' prefix is what `next-error' matches on; the text
properties are what this package itself reads, so a path containing a
colon still visits correctly."
  (let ((from (point))
        (anchor (format "%s:%s:%s:" path (or start 1) (or end start 1))))
    (insert (format "%s%s %s\n" anchor
                    (make-string (max 1 (- 46 (length anchor))) ?\s)
                    text))
    (put-text-property from (point) 'legu-path path)
    (put-text-property from (point) 'legu-start (or start 1))
    (put-text-property from (point) 'legu-end (or end start 1))
    (put-text-property from (point) 'legu-kind kind)))

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

(defun legu-list--insert-stale (snapshot)
  "Insert SNAPSHOT's stale regions."
  (unless (eq legu-list--filter 'unread)
    (let ((rows nil))
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
        (insert (propertize (format "\nSTALE  %d region%s\n" (length rows)
                                    (if (= 1 (length rows)) "" "s"))
                            'face 'legu-list-heading))
        (dolist (row rows)
          (let* ((path (car row)) (e (cdr row))
                 (state (nth 3 e))
                 (record (legu-list--record path (or (nth 0 e) 1)))
                 (when-read (and record (alist-get 'timestamp record))))
            (legu-list--row
             path (nth 0 e) (nth 1 e) 'stale
             (format "%-8s %-18s %s"
                     (propertize (or state "stale") 'face
                                 (if (equal state "missing") 'legu-missing 'legu-stale))
                     (or (nth 2 e) "")
                     (if when-read (format "read %s" (substring when-read 0 10)) "")))))))))

(defun legu-list--insert-next (snapshot)
  "Insert SNAPSHOT's reading queue."
  (unless (eq legu-list--filter 'stale)
    (let ((rows (seq-filter (lambda (r) (legu-list--scoped-p (plist-get r :path)))
                            (plist-get snapshot :queue))))
      (when rows
        (insert (propertize (format "\nNEXT  %d file%s\n" (length rows)
                                    (if (= 1 (length rows)) "" "s"))
                            'face 'legu-list-heading))
        (dolist (r rows)
          (let ((ranges (plist-get r :ranges)))
            (legu-list--row
             (plist-get r :path)
             (and ranges (car (car ranges)))
             (and ranges (cdr (car ranges)))
             'next
             (format "%5d unread %5d stale   %s"
                     (plist-get r :unreviewed) (plist-get r :stale)
                     (legu-format-ranges ranges)))))))))


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
  (let ((row (legu-list--at-point)))
    (unless row (user-error "legu: no row at point"))
    (let ((file (expand-file-name (plist-get row :path) legu-list--root)))
      (unless (file-exists-p file)
        (user-error "legu: %s no longer exists" (plist-get row :path)))
      (if other-window (find-file-other-window file) (find-file file))
      (goto-char (point-min))
      (forward-line (1- (or (plist-get row :start) 1))))))

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
