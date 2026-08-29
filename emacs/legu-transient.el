;;; legu-transient.el --- The legu menu  -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Jonas Rodrigues
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; One transient, no sub-prefixes.  Every key here is also reachable from
;; `C-c r'; the popup is a discoverability surface and the home of the one
;; sticky setting.  The coverage line reads the cached snapshot and never
;; shells out: a `:description' runs on every redisplay.

;;; Code:

(require 'transient)
(require 'legu)

(defun legu-transient--heading ()
  "The coverage line at the top of the menu."
  (let* ((root (or legu--root (legu-root)))
         (snapshot (and root (legu-snapshot root)))
         (cov (plist-get snapshot :coverage))
         (lines (and cov (max 1 (plist-get cov :lines)))))
    (concat
     (propertize "legu" 'face 'transient-heading)
     (if (null cov)
         "  no snapshot yet"
       (format " — %.0f%% read · %.1f%% stale · %.0f%% never read"
               (* 100.0 (/ (float (plist-get cov :reviewed)) lines))
               (* 100.0 (/ (float (plist-get cov :stale)) lines))
               (* 100.0 (/ (float (plist-get cov :never)) lines))))
     "   "
     (propertize (if snapshot (legu-snapshot-age-string snapshot) "") 'face 'shadow))))

(transient-define-infix legu-transient--reviewer ()
  "Who is doing the reading.  Sticky, and empty means git's own answer."
  :class 'transient-lisp-variable
  :variable 'legu-reviewer
  :description "reviewer"
  :reader (lambda (prompt _initial _history)
            (let ((s (read-string prompt (or legu-reviewer ""))))
              (if (string-empty-p (string-trim s)) nil s))))

;;;###autoload (autoload 'legu-dispatch "legu-transient" nil t)
(transient-define-prefix legu-dispatch ()
  "Review coverage for this repository."
  :refresh-suffixes t
  [:description legu-transient--heading
   ["Read"
    ("r" "mark to point" legu-mark)
    ("R" "mark whole file" legu-mark-file)
    ("SPC" "set frontier" legu-set-frontier)]
   ["Move"
    ("n" "next gap" legu-next-gap)
    ("]" "next stale" legu-next-stale)
    ("J" "next file" legu-next-file)]
   ["Store"
    ("k" "forget region" legu-forget)
    ("t" "anchor ticket" legu-ticket)
    ("T" "visit ticket" legu-visit-ticket)]]
  [["Query"
    ("." "describe at point" legu-describe-region)
    ("s" "diff stale region" legu-diff-stale)
    ("f" "failed writes" legu-list-failures)]
   ["Repo"
    ("l" "queue buffer" legu-list)
    ("c" "coverage" legu-coverage)
    ("g" "refresh" legu-refresh)]
   ["Display"
    ("h" "toggle highlights" legu-toggle-highlights)
    ("m" "file map" legu-header-line-mode)
    ("-r" legu-transient--reviewer)]]
  [:if legu-transient--store-broken-p
   ("!" "visit the broken sidecar" legu-visit-broken-store)])

(defun legu-transient--store-broken-p ()
  "Whether this repository's store is currently unreadable."
  (let ((root (or legu--root (legu-root))))
    (and root (eq (plist-get (legu-snapshot root) :state) 'error))))

(provide 'legu-transient)
;;; legu-transient.el ends here
