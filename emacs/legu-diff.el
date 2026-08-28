;;; legu-diff.el --- What changed since you read it  -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Jonas Rodrigues
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; When legu says a region you read has changed, the next thing you want is
;; the diff.  The sidecar records the commit the region was read at, so
;; `git diff <commit> -- <path>' is exactly the right question.
;;
;; Stock `diff-mode' in a bottom side window, with the window configuration
;; restored on `q' so you never lose your place.  This package owns two keys
;; and a header line, and no renderer of its own: a diff UI is a non-goal.

;;; Code:

(require 'diff-mode)
(require 'legu)

(defvar-local legu-diff--saved-configuration nil)
(defvar-local legu-diff--source nil
  "Plist naming the source buffer, path and region this diff came from.")

(defvar-keymap legu-diff-mode-map
  :parent diff-mode-map
  "r" #'legu-diff-remark
  "e" #'legu-diff-ediff
  "q" #'legu-diff-quit)

(define-derived-mode legu-diff-mode diff-mode "legu-diff"
  "What changed in a region since it was read.

\\{legu-diff-mode-map}"
  (setq buffer-read-only t))

(defun legu-diff--record-at-point ()
  "The stale record covering point, with its stored provenance."
  (let* ((line (legu--line-number))
         ;; A stale region is shown where it is now, which is rarely where it
         ;; was recorded; the nearest record is the one being asked about.
         (record (legu-region-record-nearest legu--root legu--relpath line)))
    (unless record
      (user-error "legu: %s has no reviewed region" (or legu--relpath "this file")))
    record))

;;;###autoload
(defun legu-diff-stale (&optional ediff)
  "Show what changed in the region at point since it was read.
With a prefix argument EDIFF, run `ediff' against that commit instead."
  (interactive "P")
  (unless legu--root (user-error "legu: not in a legu repository"))
  (let* ((line (legu--line-number))
         (record (legu-diff--record-at-point))
         (commit (alist-get 'commit record))
         ;; Where the region is NOW, not where it was recorded: re-marking the
         ;; stored coordinates of a region that has since moved would record
         ;; lines nobody has read.
         (here (or (legu--ranges-member (plist-get legu--painted :stale) line)
                   (legu--ranges-member (plist-get legu--painted :reviewed) line)))
         (start (if here (car here) (alist-get 'start record)))
         (end (if here (cdr here) (alist-get 'end record)))
         (path legu--relpath)
         (root legu--root)
         (source (current-buffer))
         ;; Only the CLI may say "stale"; without a trusted snapshot the
         ;; honest label is that we do not currently know.
         (state (cond
                 ((legu--ranges-member (plist-get legu--painted :stale) line) "stale")
                 ((legu--ranges-member (plist-get legu--painted :reviewed) line) "reviewed")
                 (t "unverified"))))
    (when (or (null commit) (equal commit "-"))
      (user-error "legu: that region was recorded outside git; there is no diff"))
    (if ediff
        (legu-diff--ediff root path commit)
      (let* ((configuration (current-window-configuration))
             (buffer (get-buffer-create (format "*legu-diff: %s*" path)))
             (default-directory root)
             (output (with-output-to-string
                       (with-current-buffer standard-output
                         (call-process "git" nil t nil
                                       "--no-pager" "diff" commit "--" path)))))
        (with-current-buffer buffer
          (let ((inhibit-read-only t))
            (erase-buffer)
            (insert (if (string-empty-p output)
                        "no textual diff — the file may have been renamed or rewritten\n"
                      output)))
          (legu-diff-mode)
          (setq legu-diff--saved-configuration configuration
                legu-diff--source (list :buffer source :path path
                                        :start start :end end :commit commit))
          (setq header-line-format
                (list (format " %s  %s:%d-%d   read %s by %s at %s"
                              (propertize state 'face
                                          (pcase state
                                            ("stale" 'legu-stale)
                                            ("reviewed" 'legu-reviewed)
                                            (_ 'legu-unverified)))
                              path start end
                              (substring (or (alist-get 'timestamp record) "?") 0
                                         (min 10 (length (or (alist-get 'timestamp record) "?"))))
                              (or (alist-get 'reviewer record) "?")
                              (substring commit 0 (min 8 (length commit))))
                      (propertize "   [r] re-mark   [e] ediff   [q] quit"
                                  'face 'legu-list-count)))
          (goto-char (point-min))
          (legu-diff--goto-region start end))
        (display-buffer buffer '(display-buffer-in-side-window
                                 (side . bottom) (window-height . 0.4)))
        (select-window (get-buffer-window buffer))))))

(defun legu-diff--goto-region (start end)
  "Move point to the first hunk touching lines START..END."
  (goto-char (point-min))
  (let ((found nil))
    (while (and (not found)
                (re-search-forward "^@@ -[0-9]+\\(?:,[0-9]+\\)? \\+\\([0-9]+\\)\\(?:,\\([0-9]+\\)\\)? @@"
                                   nil t))
      (let* ((from (string-to-number (match-string 1)))
             (len (if (match-string 2) (string-to-number (match-string 2)) 1))
             (to (+ from len)))
        (when (and (<= from end) (>= to start))
          (setq found t)
          (goto-char (line-beginning-position)))))
    (unless found (goto-char (point-min)))))

(defun legu-diff--ediff (root path commit)
  "Ediff PATH under ROOT against COMMIT."
  (require 'ediff)
  (let ((default-directory root))
    (ediff-revision (expand-file-name path root) nil)
    (message "legu: compare against %s" (substring commit 0 (min 8 (length commit))))))

(defun legu-diff-remark ()
  "Re-mark the region this diff describes, and restore the layout."
  (interactive)
  (let* ((source legu-diff--source)
         (buffer (plist-get source :buffer))
         (start (plist-get source :start))
         (end (plist-get source :end))
         (configuration legu-diff--saved-configuration))
    (unless (buffer-live-p buffer) (user-error "legu: the source buffer is gone"))
    (with-current-buffer buffer
      (goto-char (legu--line-position start))
      (legu-mark (cons start (min end (legu--buffer-lines)))))
    (quit-window t)
    (when configuration (set-window-configuration configuration))))

(defun legu-diff-ediff ()
  "Ediff this file against the commit it was read at."
  (interactive)
  (let ((source legu-diff--source))
    (legu-diff--ediff (with-current-buffer (plist-get source :buffer) legu--root)
                      (plist-get source :path)
                      (plist-get source :commit))))

(defun legu-diff-quit ()
  "Close the diff and put the windows back."
  (interactive)
  (let ((configuration legu-diff--saved-configuration))
    (quit-window t)
    (when configuration (set-window-configuration configuration))))

(provide 'legu-diff)
;;; legu-diff.el ends here
