;;; legu-overlay.el --- Gutter indicators for legu  -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Jonas Rodrigues
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Two channels, and only two: the gutter glyph carries the review state,
;; the background is reserved for the alarm.  Reviewed code is the eventual
;; normal state of a well read file, so tinting it would mean tinting almost
;; everything and fighting font-lock for hours.  Absence is the signal for
;; unread: a file nobody has read looks exactly like a file without the mode.
;;
;; Overlays, never text properties: text properties travel with
;; `kill-region' and `yank', so cutting a reviewed block and pasting it
;; elsewhere would mint a reviewed mark legu never issued.

;;; Code:

(require 'seq)
(require 'cl-lib)

;;;###autoload
(defgroup legu nil
  "Human review coverage: which lines of this repository have been read."
  :group 'tools
  :prefix "legu-")

(defcustom legu-indicator-style 'fringe
  "How review state is drawn beside each line.
`fringe' needs a graphical frame; windows on a terminal fall back to
`margin' by themselves.  `face-only' draws no glyph, for users whose
fringe already belongs to `diff-hl'."
  :type '(choice (const fringe) (const margin) (const face-only))
  :group 'legu)

(defcustom legu-indicator-side 'left
  "Which side of the window the indicators are drawn on."
  :type '(choice (const left) (const right))
  :group 'legu)

(defcustom legu-ascii-glyphs nil
  "Use ASCII margin glyphs even where the nicer ones are displayable."
  :type 'boolean
  :group 'legu)

(defcustom legu-margin-glyphs
  '((reviewed . "│") (stale . "!") (note . "*")
    (unverified . ":") (frontier . ">") (ignored . "~"))
  "Glyphs used in the margin, and on terminals."
  :type '(alist :key-type symbol :value-type string)
  :group 'legu)

(defcustom legu-margin-ascii-glyphs
  '((reviewed . "|") (stale . "!") (note . "*")
    (unverified . ":") (frontier . ">") (ignored . "~"))
  "Glyphs used in the margin when ASCII is all that will render."
  :type '(alist :key-type symbol :value-type string)
  :group 'legu)


;;;; Faces

(defface legu-reviewed
  '((((background light)) :foreground "#6a8f6a")
    (((background dark))  :foreground "#5f7f5f"))
  "Face for the gutter bar beside a line that has been read."
  :group 'legu)

(defface legu-stale '((t :inherit warning))
  "Face for the gutter bar beside a line whose content changed since it was read."
  :group 'legu)

(defface legu-stale-region
  '((((background light)) :background "#fdf3e3" :extend t)
    (((background dark))  :background "#332b1c" :extend t))
  "Face tinting a region that needs re-reading.  The only background legu paints."
  :group 'legu)

(defface legu-note '((t :inherit font-lock-constant-face))
  "Face for the gutter dot beside a region carrying a ticket reference."
  :group 'legu)

(defface legu-unverified '((t :inherit shadow))
  "Face for indicators legu cannot currently vouch for."
  :group 'legu)

(defface legu-frontier '((t :inherit font-lock-keyword-face))
  "Face for the reading frontier marker."
  :group 'legu)

(defface legu-ignored '((t :inherit shadow))
  "Face marking a file outside the eligible set."
  :group 'legu)

(defface legu-missing '((t :inherit error))
  "Face for a region whose file is gone."
  :group 'legu)

(defface legu-list-heading '((t :inherit font-lock-doc-face :weight bold))
  "Face for section headings in the queue buffer."
  :group 'legu)

(defface legu-list-count '((t :inherit font-lock-comment-face))
  "Face for counts in the queue buffer."
  :group 'legu)

(defface legu-error '((t :inherit error))
  "Face for the broken-store lighter and banner."
  :group 'legu)


;;;; Fringe bitmaps

(when (fboundp 'define-fringe-bitmap)
  ;; A solid 2px bar, repeated down the line: the diff-hl idiom.
  (define-fringe-bitmap 'legu-bmp-bar [192] nil nil '(center t))
  ;; Dashes, so stale reads differently from reviewed without colour alone.
  (define-fringe-bitmap 'legu-bmp-stale [224 224 0 0] nil nil '(center t))
  ;; A thin dotted line for anything legu cannot currently vouch for.
  (define-fringe-bitmap 'legu-bmp-dashed [128 0] nil nil '(center t))
  ;; One dot, on the first line of a noted region only.
  (define-fringe-bitmap 'legu-bmp-note [0 0 96 240 240 96 0 0] nil nil 'center)
  ;; A right pointing triangle: you are here.
  (define-fringe-bitmap 'legu-bmp-frontier
    [128 192 224 240 240 224 192 128] nil nil 'center))

(defconst legu--bitmaps
  '((reviewed . legu-bmp-bar)
    (stale . legu-bmp-stale)
    (unverified . legu-bmp-dashed)
    (note . legu-bmp-note)
    (frontier . legu-bmp-frontier)
    (ignored . legu-bmp-dashed))
  "Fringe bitmap for each indicator state.")

(defconst legu--state-faces
  '((reviewed . legu-reviewed)
    (stale . legu-stale)
    (unverified . legu-unverified)
    (note . legu-note)
    (frontier . legu-frontier)
    (ignored . legu-ignored))
  "Face for each indicator state.")


;;;; Style resolution

(defvar-local legu--overlays nil
  "Overlays this buffer has painted.")
(defvar-local legu--style nil
  "The indicator style this buffer was last painted with.")
(defvar-local legu--header-string nil
  "Precomputed header line map, never recomputed inside `:eval'.")
;; Forward declaration: the mode is defined at the bottom of this file.
(defvar legu-header-line-mode)

(defun legu-overlay-effective-style ()
  "The style to paint with, given where this buffer is displayed.
A `(left-fringe …)' display spec renders nothing at all on a terminal,
so any window on a text frame forces the whole buffer to the margin."
  (let ((windows (get-buffer-window-list nil nil t)))
    (cond
     ((eq legu-indicator-style 'face-only) 'face-only)
     ((eq legu-indicator-style 'margin) 'margin)
     ((null windows) (if (display-graphic-p) 'fringe 'margin))
     ((seq-some (lambda (w) (not (display-graphic-p (window-frame w)))) windows) 'margin)
     (t 'fringe))))

(defun legu-overlay-style-changed-p ()
  "Whether the effective style differs from the one last painted."
  (and legu--style (not (eq legu--style (legu-overlay-effective-style)))))

(defun legu--glyph (state)
  "The margin glyph string for STATE."
  (let ((table (if (or legu-ascii-glyphs
                       (not (char-displayable-p
                             (aref (or (alist-get 'reviewed legu-margin-glyphs) "|") 0))))
                   legu-margin-ascii-glyphs
                 legu-margin-glyphs)))
    (or (alist-get state table)
        (alist-get state legu-margin-ascii-glyphs)
        "|")))

(defun legu--indicator (state style)
  "A `before-string' drawing STATE in STYLE, or nil."
  (let ((face (alist-get state legu--state-faces)))
    (pcase style
      ('face-only nil)
      ('fringe
       (propertize " " 'display
                   (list (if (eq legu-indicator-side 'right) 'right-fringe 'left-fringe)
                         (alist-get state legu--bitmaps)
                         face)))
      (_
       (propertize " " 'display
                   `((margin ,(if (eq legu-indicator-side 'right)
                                  'right-margin 'left-margin))
                     ,(propertize (legu--glyph state) 'face face)))))))

(defun legu--install-margins (style)
  "Give this buffer a margin column when STYLE needs one.
A bare `set-window-margins' is undone by the next `set-window-buffer',
so the width has to live in the buffer and be pushed to its windows."
  (let ((want (if (eq style 'margin) 1 0)))
    (if (eq legu-indicator-side 'right)
        (unless (eql right-margin-width want) (setq-local right-margin-width want))
      (unless (eql left-margin-width want) (setq-local left-margin-width want)))
    (dolist (win (get-buffer-window-list nil nil t))
      (set-window-buffer win (current-buffer)))))


;;;; Painting

(defun legu-overlay-clear ()
  "Remove every overlay this package painted in the current buffer."
  (mapc #'delete-overlay legu--overlays)
  (setq legu--overlays nil)
  (remove-overlays (point-min) (point-max) 'legu t)
  (setq legu--style nil))

(defun legu-overlay-dim ()
  "Re-face every indicator as unverified, deleting none.
The overlays still say roughly where you had read, and Emacs moves them
across every edit in C for free."
  (let ((style (or legu--style (legu-overlay-effective-style))))
    (dolist (ov legu--overlays)
      (when (overlay-buffer ov)
        (overlay-put ov 'face nil)
        (when (overlay-get ov 'before-string)
          (overlay-put ov 'before-string (legu--indicator 'unverified style)))))))

(defvar-local legu--line-cache nil
  "Cons of (LINE . POSITION) from the last `legu--line-bounds' call.")

(defun legu--line-bounds (line)
  "Buffer positions spanning file line LINE, including its newline.
Walks on from the previous line rather than from `point-min': painting a
ten thousand line file one line at a time is otherwise quadratic."
  (save-restriction
    (widen)
    (save-excursion
      (if (and legu--line-cache (<= (car legu--line-cache) line))
          (progn (goto-char (cdr legu--line-cache))
                 (forward-line (- line (car legu--line-cache))))
        (goto-char (point-min))
        (forward-line (1- line)))
      (setq legu--line-cache (cons line (point)))
      (cons (point) (min (point-max) (line-beginning-position 2))))))

(defun legu--make-overlay (line state style &optional background)
  "Paint LINE in STATE and STYLE, with BACKGROUND when asked."
  (let* ((bounds (legu--line-bounds line))
         (beg (car bounds)) (end (cdr bounds)))
    ;; `legu--line-bounds' answers in absolute positions, so the guard has to
    ;; be absolute too, or a narrowed buffer paints nothing below its end.
    (when (<= beg (save-restriction (widen) (point-max)))
      (let ((ov (make-overlay beg end nil nil nil)))
        (overlay-put ov 'legu t)
        (overlay-put ov 'legu-state state)
        ;; Deleting the text under an overlay must not leave a zombie.  A
        ;; zero length overlay would be evaporated at birth, so the flag
        ;; goes on only where the line actually has extent.
        (when (> end beg) (overlay-put ov 'evaporate t))
        (overlay-put ov 'priority (pcase state
                                    ('reviewed 10) ('stale 20) ('unverified 10)
                                    ('note 30) ('frontier 30) (_ 15)))
        (when background (overlay-put ov 'face background))
        (when-let* ((indicator (legu--indicator state style)))
          (overlay-put ov 'before-string indicator))
        (overlay-put ov 'help-echo
                     (pcase state
                       ('reviewed "legu: read")
                       ('stale "legu: read, but the content has changed")
                       ('note "legu: ticket attached")
                       ('unverified "legu: unverified — the file on disk has moved on")
                       ('frontier "legu: reading frontier")
                       ('ignored "legu: outside the eligible set")
                       (_ "legu")))
        (push ov legu--overlays)
        ov))))

(cl-defun legu-overlay-paint (&key reviewed stale notes frontier unverified out-of-scope)
  "Paint the current buffer.

REVIEWED and STALE are line range sets, NOTES a list of first lines,
FRONTIER a line number.  With UNVERIFIED, everything is drawn in the
unverified style and no background is tinted: the file on disk is not
the file on screen, and legu only ever describes the file on disk."
  (legu-overlay-clear)
  (setq legu--line-cache nil)
  (let ((style (legu-overlay-effective-style)))
    (setq legu--style style)
    (legu--install-margins style)
    (if out-of-scope
        (legu--make-overlay 1 'ignored style)
      (let ((claimed (make-hash-table :test #'eql)))
        ;; Glyph precedence: a ticket, then the frontier, then the alarm.
        (dolist (line notes)
          (when (and line (not (gethash line claimed)))
            (puthash line t claimed)
            (legu--make-overlay line 'note style)))
        (when (and frontier (not (gethash frontier claimed)))
          (puthash frontier t claimed)
          (legu--make-overlay frontier 'frontier style))
        (dolist (range stale)
          (let ((line (car range)))
            (while (<= line (cdr range))
              (unless (gethash line claimed)
                (puthash line t claimed)
                (legu--make-overlay line (if unverified 'unverified 'stale) style
                                    (unless unverified 'legu-stale-region)))
              (setq line (1+ line)))))
        (dolist (range reviewed)
          (let ((line (car range)))
            (while (<= line (cdr range))
              (unless (gethash line claimed)
                (puthash line t claimed)
                (legu--make-overlay line (if unverified 'unverified 'reviewed) style))
              (setq line (1+ line)))))))
    (legu--header-recompute reviewed stale)))


;;;; The optional header line map

(defcustom legu-header-line-slices 0
  "Characters in the header line file map.  Zero fits the window."
  :type 'integer
  :group 'legu)

(defun legu--header-recompute (reviewed stale)
  "Rebuild the header line map from REVIEWED and STALE.
Computed here, never inside `:eval': that runs on every redisplay."
  (when legu-header-line-mode
    (let* ((total (max 1 (line-number-at-pos (point-max))))
           (width (if (> legu-header-line-slices 0)
                      legu-header-line-slices
                    (max 20 (- (window-body-width) 2))))
           (out (make-string width ?·))
           (mark (lambda (ranges char face)
                   (dolist (r ranges)
                     (let ((i (/ (* (1- (car r)) width) total))
                           (j (/ (* (1- (cdr r)) width) total)))
                       (while (<= i (min j (1- width)))
                         (aset out i char)
                         (put-text-property i (1+ i) 'face face out)
                         (setq i (1+ i))))))))
      (funcall mark reviewed ?▁ 'legu-reviewed)
      (funcall mark stale ?▄ 'legu-stale)
      (setq legu--header-string out))))

(define-minor-mode legu-header-line-mode
  "Show a one line proportional map of this file's review state."
  :group 'legu
  (if legu-header-line-mode
      (setq header-line-format '(:eval legu--header-string))
    (setq header-line-format nil)))

(provide 'legu-overlay)
;;; legu-overlay.el ends here
