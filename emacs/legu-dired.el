;;; legu-dired.el --- Review coverage beside each file in dired  -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Jonas Rodrigues
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; A fixed-width column before the filename in dired: reviewed percent,
;; then stale percent when it is not zero.  Unreviewed is the remainder.
;; A directory's numbers are line-weighted sums over the eligible files
;; beneath it.  Everything is read from the cached snapshot; nothing here
;; ever runs the CLI.

;;; Code:

(require 'dired)
(require 'legu)

;; Forward declaration: the minor mode is defined at the bottom of this file.
(defvar legu-dired-mode)


;;;; Sums and formatting
;;
;; A cell is the coverage of one file or directory as the column needs it:
;; a plist of :total, :reviewed, :stale and :uncertain lines.

(defun legu-dired--ancestors (path)
  "The directories above PATH, nearest first, ending with the root \"\"."
  (let ((out nil) (dir (file-name-directory path)))
    (while dir
      (let ((key (directory-file-name dir)))
        (push key out)
        (setq dir (file-name-directory key))))
    (nreverse (cons "" out))))

(defun legu-dired--directory-cells (rows within uncertain-p)
  "Per-directory cells summed over ROWS, for WITHIN and the directories beneath it.
WITHIN is a repository-relative directory, \"\" for the root.  Keys are
directories in the same form; a directory with no eligible file beneath
it has no key.  UNCERTAIN-P is called with each path; a directory is
uncertain when any file beneath it is."
  (let ((cells (make-hash-table :test #'equal))
        (prefix (if (equal within "") "" (concat within "/"))))
    (maphash
     (lambda (path row)
       (when (string-prefix-p prefix path)
         (let ((uncertain (funcall uncertain-p path)))
           (dolist (key (legu-dired--ancestors path))
             (when (or (equal key within) (string-prefix-p prefix key))
               (let ((cell (or (gethash key cells)
                               (puthash key (list :total 0 :reviewed 0 :stale 0
                                                  :uncertain nil)
                                        cells))))
                 (plist-put cell :total (+ (plist-get cell :total) (plist-get row :total)))
                 (plist-put cell :reviewed (+ (plist-get cell :reviewed)
                                              (plist-get row :reviewed)))
                 (plist-put cell :stale (+ (plist-get cell :stale) (plist-get row :stale)))
                 (when uncertain (plist-put cell :uncertain t))))))))
     rows)
    cells))

(defconst legu-dired--column-width 8
  "Characters in the column, not counting the space after it.
Wide enough for the widest cell, \"50% 50%?\".")

(defun legu-dired--format-cell (cell)
  "CELL as the fixed-width column text.
CELL is a plist of :total, :reviewed, :stale and :uncertain lines, or
nil for a file or directory outside the eligible set.  Reviewed is
floored and stale is ceilinged, so neither rounding error hides work;
stale is blank at zero; \"?\" marks numbers the snapshot cannot vouch
for; a dash means there is nothing to count.  The faces are the gutter's
own, so the column doubles as its legend; 100% is bold because it is a
state, not a score -- there are no colour thresholds."
  (let* ((total (or (plist-get cell :total) 0))
         (text
          (if (= total 0)
              (propertize "—" 'face 'legu-ignored)
            (let ((reviewed (/ (* 100 (plist-get cell :reviewed)) total))
                  (stale (/ (+ (* 100 (plist-get cell :stale)) total -1) total)))
              (concat
               (propertize (format "%d%%" reviewed)
                           'face (if (= reviewed 100)
                                     '(bold legu-reviewed)
                                   'legu-reviewed))
               (when (> stale 0)
                 (concat " " (propertize (format "%d%%" stale) 'face 'legu-stale)))
               (when (plist-get cell :uncertain)
                 (propertize "?" 'face 'legu-unverified)))))))
    (concat text (make-string (max 0 (- legu-dired--column-width (length text))) ?\s))))


;;;; Rendering

(defvar dirvish--props)

(defun legu-dired--dirvish-p ()
  "Whether this is a dirvish buffer, which draws its own attributes."
  (or (derived-mode-p 'dirvish-directory-view-mode)
      (and (boundp 'dirvish--props)
           (hash-table-p dirvish--props)
           (gethash :dv dirvish--props)
           t)))

(defun legu-dired-eligible-p ()
  "Whether this buffer can carry the column: local dired under a store."
  (and (derived-mode-p 'dired-mode)
       (not (file-remote-p default-directory))
       (not (legu-dired--dirvish-p))
       (legu--root-cheap default-directory)
       t))

(defun legu-dired--key (root file)
  "FILE as a repository-relative key under ROOT: \"\" for ROOT, nil outside it."
  (let ((rel (directory-file-name (legu--relative root file))))
    (cond ((equal rel ".") "")
          ((or (equal rel "..") (string-prefix-p "../" rel)) nil)
          (t rel))))

(defun legu-dired--uncertain-p (root snapshot path)
  "Whether SNAPSHOT cannot vouch for PATH under ROOT: the file is newer."
  (not (legu-snapshot-trusted-p snapshot (expand-file-name path root))))

(defun legu-dired--file-cell (root snapshot key)
  "The cell for the eligible file KEY under ROOT, or nil."
  (when-let* ((row (gethash key (plist-get snapshot :rows))))
    (list :total (plist-get row :total)
          :reviewed (plist-get row :reviewed)
          :stale (plist-get row :stale)
          :uncertain (legu-dired--uncertain-p root snapshot key))))

(defun legu-dired--put-overlay (text)
  "Draw TEXT before the filename on this line."
  (when (dired-move-to-filename)
    (let* ((start (point))
           (end (save-excursion (dired-move-to-end-of-filename t) (point)))
           (ov (make-overlay start (max end (1+ start)))))
      (overlay-put ov 'legu-dired t)
      (overlay-put ov 'evaporate t)
      (overlay-put ov 'before-string (concat text " ")))))

(defun legu-dired--render ()
  "Draw the column on every file line of the accessible part of the buffer.
Reads the cached snapshot only.  Without rows -- none yet, or an error
before the first one -- the column stays blank."
  (let* ((root legu--root)
         (snapshot (legu-snapshot root))
         (rows (plist-get snapshot :rows)))
    (remove-overlays (point-min) (point-max) 'legu-dired t)
    (when rows
      (let* ((within (legu-dired--key root default-directory))
             (beneath (if (equal within "") "" (concat within "/")))
             (cells (and within
                         (legu-dired--directory-cells
                          rows within
                          (lambda (path) (legu-dired--uncertain-p root snapshot path))))))
        (save-excursion
          (goto-char (point-min))
          (while (not (eobp))
            (when-let* ((file (dired-get-filename nil t))
                        (key (legu-dired--key root file)))
              (if (file-directory-p file)
                  ;; Only directories inside the listed one were summed;
                  ;; `..' above it would draw a false dash.
                  (when (and cells
                             (or (equal key within) (string-prefix-p beneath key)))
                    (legu-dired--put-overlay
                     (legu-dired--format-cell (gethash key cells))))
                (legu-dired--put-overlay
                 (legu-dired--format-cell (legu-dired--file-cell root snapshot key)))))
            (forward-line 1)))))))

(defun legu-dired--render-all ()
  "Redraw the whole buffer, however it is narrowed."
  (save-restriction
    (widen)
    (legu-dired--render)))

(defun legu-dired-refresh-buffers (root)
  "Redraw every dired buffer showing ROOT, because a snapshot landed."
  (dolist (buf (buffer-list))
    (with-current-buffer buf
      (when (and legu-dired-mode (equal legu--root root))
        (legu-dired--render-all)))))


;;;; The mode

(defun legu-dired--teardown ()
  "Remove the column and this buffer's hooks."
  (save-restriction
    (widen)
    (remove-overlays (point-min) (point-max) 'legu-dired t))
  (remove-hook 'dired-after-readin-hook #'legu-dired--render t)
  (remove-hook 'dired-subtree-after-insert-hook #'legu-dired--render-all t)
  (remove-hook 'kill-buffer-hook #'legu-dired--teardown t)
  (when legu--root (legu--unwatch-maybe legu--root)))

;;;###autoload
(define-minor-mode legu-dired-mode
  "Show review coverage in a column before each filename.
Reviewed percent, then stale percent when it is not zero; unreviewed is
the remainder.  A directory sums the eligible files beneath it, line for
line.  Read-only: marking happens in the file, or from the queue."
  :lighter nil
  (if legu-dired-mode
      (let ((root (and (legu-dired-eligible-p) (legu-root default-directory))))
        (if (null root)
            (progn
              (setq legu-dired-mode nil)
              (user-error "legu: not a local dired buffer under a .review store"))
          (setq legu--root root)
          ;; `dired-insert-subdir' runs the hook narrowed to what it inserted;
          ;; a revert runs it once over the whole buffer.
          (add-hook 'dired-after-readin-hook #'legu-dired--render nil t)
          (add-hook 'dired-subtree-after-insert-hook #'legu-dired--render-all nil t)
          (add-hook 'kill-buffer-hook #'legu-dired--teardown nil t)
          (legu--watch-store root)
          (legu-dired--render-all)
          (legu--first-visit root)))
    (legu-dired--teardown)))

(provide 'legu-dired)
;;; legu-dired.el ends here
