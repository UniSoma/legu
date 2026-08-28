;;; legu-evil.el --- legu under evil and Doom  -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Jonas Rodrigues
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Without this file the queue buffer is not merely awkward under evil, it
;; is wrong.  `legu-list-mode' derives from `compilation-mode', so
;; evil-collection's compile bindings reach it through the parent keymap:
;; RET runs `compile-goto-error' instead of `legu-list-visit' (which reads
;; text properties, and so survives a path containing a colon), `gr' runs
;; `recompile' on a buffer no compilation produced, and every legu action
;; key -- o r s c x a i d p -- is bound to `ignore'.  What is left is a
;; buffer where RET is subtly wrong and nothing else does anything at all.
;;
;; The keys below follow evil-collection's own conventions: motions stay
;; motions, `gr' refreshes, `q' quits, and the actions take keys a
;; read-only buffer frees up.  Two are deliberate exceptions.  `?' opens
;; the transient instead of searching backwards, which is the bargain
;; evil-collection already strikes in magit; and the diff is on `d', not
;; the `s' the Emacs keymap uses, because Doom enables evil-snipe, whose
;; minor mode map outranks every major mode's -- `s' there is a snipe, and
;; no keymap can take it back.
;;
;; Bindings live on `legu-list-mode-map' itself, whose auxiliary keymap
;; outranks its parent's, so this works whether or not evil-collection is
;; installed, and in either load order.

;;; Code:

(require 'legu)
(require 'legu-list)
(require 'legu-diff)

(declare-function evil-define-key* "evil-core")
(declare-function evil-visual-state-p "evil-states")
(declare-function evil-exit-visual-state "evil-states")

(defconst legu-evil--selection-commands
  '(legu-mark legu-note legu-forget legu-list-mark)
  "Commands that consume a selection, and so should end visual state.")

(defun legu-evil--exit-visual-state (&rest _)
  "Leave visual state once a legu command has consumed the selection.
Evil keeps a selection up after a command it does not know about, so
without this the highlight outlives the mark it produced, and the next
key acts on a range the user believes is spent."
  (when (and (fboundp 'evil-visual-state-p) (evil-visual-state-p))
    (evil-exit-visual-state)))

;;;###autoload
(defun legu-evil-setup ()
  "Bind legu's queue and diff buffers the way evil users expect.
Called automatically when evil is present, unless `legu-evil-integration'
is nil.  Also suitable for `evil-collection-setup-hook'."
  (evil-define-key* 'normal legu-list-mode-map
    (kbd "RET") #'legu-list-visit
    (kbd "S-<return>") #'legu-list-visit-other-window
    "gd" #'legu-list-visit
    "o" #'legu-list-visit-other-window
    "go" #'legu-list-visit-other-window
    ;; Without this `gr' is evil-collection's `recompile', which in a buffer
    ;; no compilation produced is at best an error.
    "gr" #'revert-buffer
    "gf" #'legu-list-toggle-filter
    "r" #'legu-list-mark
    "d" #'legu-list-diff
    "a" #'legu-list-note
    "x" #'legu-list-forget
    "c" #'legu-coverage
    "?" #'legu-dispatch
    "g?" #'legu-dispatch
    ;; evil-collection supplies this one; evil alone does not, and there `q'
    ;; would start recording a macro.
    "q" #'quit-window)
  ;; The multi-row flow is "select rows with V, then mark them", so marking
  ;; has to exist in visual state too -- the selection is what it reads.
  ;; Only marking: `a' and `i' are visual state's text object prefixes, and
  ;; the other two act on the row at point anyway.
  (evil-define-key* 'visual legu-list-mode-map
    "r" #'legu-list-mark)
  (evil-define-key* 'normal legu-diff-mode-map
    "r" #'legu-diff-remark
    ;; Not `e' or `ge': both are taken by evil-collection's diff-mode minor
    ;; mode map, which no major mode keymap outranks.  `=' is free in a
    ;; read-only buffer and reads as "compare".
    "=" #'legu-diff-ediff
    ;; `q' is evil-collection's too, so the remap in `legu-diff-mode-map' is
    ;; what actually catches it; this binding is for evil without
    ;; evil-collection.
    "q" #'legu-diff-quit
    "ZQ" #'legu-diff-quit
    "ZZ" #'legu-diff-quit)
  ;; `legu-mode-map' is a minor mode map, so these outrank a major mode's
  ;; own bindings in every source buffer -- which is why they are confined
  ;; to two pairs of unbound bracket motions, and why they are optional.
  (when legu-evil-source-motions
    (evil-define-key* 'normal legu-mode-map
      "]r" #'legu-next-stale
      "[r" #'legu-previous-stale
      "]g" #'legu-next-gap
      "[g" #'legu-previous-gap))
  (dolist (command legu-evil--selection-commands)
    (advice-add command :after #'legu-evil--exit-visual-state)))

(defun legu-evil-teardown ()
  "Undo the advice `legu-evil-setup' installs.  Keymaps are left alone."
  (dolist (command legu-evil--selection-commands)
    (advice-remove command #'legu-evil--exit-visual-state)))

(legu-evil-setup)

(provide 'legu-evil)
;;; legu-evil.el ends here
