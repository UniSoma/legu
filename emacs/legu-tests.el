;;; legu-tests.el --- Tests for legu.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Jonas Rodrigues
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Two tiers.  The first is pure: range arithmetic, the sidecar reader, the
;; derived numbers, painting precedence, overlay lifecycle.  The second
;; drives the real legu binary against a real scratch git repository, and
;; skips itself when that binary is not installed.  A third group covers
;; evil, and skips itself when evil is not installed.
;;
;; Run them with:
;;
;;   emacs -Q --batch -L . -l legu-tests.el -f ert-run-tests-batch-and-exit
;;
;; and, to include the evil group, with evil and evil-collection on the
;; load path -- for example
;;
;;   emacs -Q --batch -L . -L ~/.emacs.d/elpa/... -l legu-tests.el \
;;         -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'legu)
(require 'legu-list)
(require 'legu-diff)
(require 'legu-dired)

(declare-function evil-local-mode "evil-core")
(declare-function evil-normal-state "evil-states")
(declare-function evil-visual-line "evil-states")
(declare-function evil-visual-state-p "evil-states")
(declare-function evil-exit-visual-state "evil-states")
(declare-function evil-normalize-keymaps "evil-core")
(declare-function evil-next-line "evil-commands")
(declare-function evil-previous-line "evil-commands")
(declare-function legu-evil--exit-visual-state "legu-evil")

(defun legu-test--binary-p ()
  "Whether the real legu CLI is available."
  (and (legu--program) t))


;;;; Range arithmetic

(ert-deftest legu-test-parse-ranges ()
  (should (equal (legu--parse-ranges "40-95,120") '((40 . 95) (120 . 120))))
  (should (equal (legu--parse-ranges "-") nil))
  (should (equal (legu--parse-ranges "") nil))
  (should (equal (legu--parse-ranges nil) nil))
  (should (equal (legu--parse-ranges "1") '((1 . 1)))))

(ert-deftest legu-test-format-ranges ()
  (should (equal (legu-format-ranges '((40 . 95) (120 . 120))) "40-95,120"))
  (should (equal (legu-format-ranges nil) "-"))
  ;; Round trip through the CLI's own display format.
  (dolist (s '("40-95,120" "1" "1-3,7-9,11" "-"))
    (should (equal (legu-format-ranges (legu--parse-ranges s)) s))))

(ert-deftest legu-test-ranges-normalize ()
  (should (equal (legu--ranges-normalize '((5 . 9) (1 . 3) (4 . 4)))
                 '((1 . 9))))
  (should (equal (legu--ranges-normalize '((1 . 3) (10 . 12)))
                 '((1 . 3) (10 . 12))))
  (should (equal (legu--ranges-normalize '((1 . 5) (3 . 9))) '((1 . 9)))))

(ert-deftest legu-test-ranges-subtract ()
  (should (equal (legu--ranges-subtract '((1 . 10)) '((4 . 6)))
                 '((1 . 3) (7 . 10))))
  (should (equal (legu--ranges-subtract '((1 . 10)) '((1 . 10))) nil))
  (should (equal (legu--ranges-subtract '((1 . 10)) nil) '((1 . 10))))
  (should (equal (legu--ranges-subtract nil '((1 . 10))) nil))
  (should (equal (legu--ranges-subtract '((1 . 5) (10 . 20)) '((3 . 12)))
                 '((1 . 2) (13 . 20)))))

(ert-deftest legu-test-ranges-complement ()
  (should (equal (legu--ranges-complement '((3 . 5)) 10)
                 '((1 . 2) (6 . 10))))
  (should (equal (legu--ranges-complement nil 4) '((1 . 4))))
  (should (equal (legu--ranges-complement '((1 . 4)) 4) nil))
  (should (equal (legu--ranges-complement nil 0) nil)))

(ert-deftest legu-test-ranges-count ()
  (should (= (legu--ranges-count '((1 . 10) (20 . 20))) 11))
  (should (= (legu--ranges-count nil) 0)))

(ert-deftest legu-test-ranges-member ()
  (should (equal (legu--ranges-member '((1 . 5) (9 . 12)) 10) '(9 . 12)))
  (should-not (legu--ranges-member '((1 . 5) (9 . 12)) 7)))


;;;; The sidecar reader

(defconst legu-test--sidecar "\
{\"schema\":3}
{\"start\":10,\"end\":20,\"reviewer\":\"a \\\"quoted\\\" name\",\"timestamp\":\"2026-08-28T10:00:28Z\",\"commit\":\"c439a98805096d822fb420ffa3a37564ad124f58\",\"file-hash\":\"be9c2c9ae93d3e3f9279aed5036406b927bac3257ea456970903bb0bcf9c65f9\",\"content-hash\":\"d65c7b\"}
{\"opaque\":true,\"ticket\":\"lgu-01k7\",\"timestamp\":\"2026-08-28T10:00:28Z\",\"commit\":\"c439a98805096d822fb420ffa3a37564ad124f58\",\"file-hash\":\"be9c2c\"}
")

(ert-deftest legu-test-sidecar-reads-a-real-sidecar ()
  (let* ((data (legu--read-sidecar legu-test--sidecar))
         (region (car (alist-get 'regions data)))
         (ticket (car (alist-get 'tickets data))))
    (should (eql 3 (alist-get 'schema data)))
    (should-not (assq 'path data))
    (should (= 1 (length (alist-get 'regions data))))
    (should (= 1 (length (alist-get 'tickets data))))
    (should (eql 10 (alist-get 'start region)))
    (should (eql 20 (alist-get 'end region)))
    (should (equal "a \"quoted\" name" (alist-get 'reviewer region)))
    (should (equal "lgu-01k7" (alist-get 'ticket ticket)))
    (should (eq t (alist-get 'opaque ticket)))
    (should-not (assq 'start ticket))))

(ert-deftest legu-test-sidecar-reads-the-escapes-json-prints ()
  (let ((data (legu--read-sidecar
               "{\"schema\":3}\n{\"reviewer\":\"a\\fb\\bc\\td\\u00e9\\\\\"}\n")))
    (should (equal (alist-get 'reviewer (car (alist-get 'regions data)))
                   "a\fb\bc\tdé\\"))))

(ert-deftest legu-test-sidecar-never-signals ()
  "Anything that is not a whole sidecar reads as nil: a line that does not
parse is not skipped, since the lines a merge conflict wraps are records."
  (dolist (bad (list "<<<<<<< HEAD\n{\"schema\":3}\n=======\n"
                     "{\"schema\":3}\n{\"start\":1,\"end\":2,\"reviewer\""
                     "{\"schema\":3}\n[1,2,3]\n"
                     "{\"schema\":3}\n\n{\"start\":1,\"end\":2,\"reviewer\":\"r\"}\n"
                     "{\"schema\":3}\n{\"start\":1,\"end\":2,\"reviewer\":\"r\"} {\"x\":1}\n"
                     "{\"schema\":3}\n{\"start\":1,\"end\":2,\"reviewer\":\"r\"}garbage\n"
                     "{\"schema\":3}\n{\"start\":1,\"end\":2,\"file-hash\":\"a\"}\n"
                     "{\"start\":1,\"end\":2,\"reviewer\":\"r\"}\n"
                     "[1,2,3]"
                     "3"
                     ""
                     "{:schema 2\n :regions [\n ]\n :tickets [\n ]}\n"))
    (should-not (legu--read-sidecar bad))))

(ert-deftest legu-test-sidecar-schema-gate ()
  (let* ((dir (make-temp-file "legu-test" t))
         (side (expand-file-name ".review/a.txt.jsonl" dir)))
    (unwind-protect
        (progn
          (make-directory (file-name-directory side) t)
          (with-temp-file side (insert "{\"schema\":4}\n"))
          (let ((legu--schema-warned nil))
            (should-not (plist-get (legu-sidecar-records dir "a.txt") :ok)))
          (with-temp-file side (insert legu-test--sidecar))
          (should (plist-get (legu-sidecar-records dir "a.txt") :ok))
          (should (= 1 (length (plist-get (legu-sidecar-records dir "a.txt") :regions)))))
      (delete-directory dir t))))

(ert-deftest legu-test-sidecar-missing-sidecar-is-ok-and-empty ()
  (let ((dir (make-temp-file "legu-test" t)))
    (unwind-protect
        (let ((r (legu-sidecar-records dir "nope.txt")))
          (should (plist-get r :ok))
          (should-not (plist-get r :regions)))
      (delete-directory dir t))))


;;;; Derived numbers

(defun legu-test--rows (specs)
  "Build a snapshot row table from SPECS of (path total reviewed stale ranges)."
  (let ((rows (make-hash-table :test #'equal)))
    (dolist (s specs)
      (puthash (nth 0 s)
               (list :total (nth 1 s) :reviewed (nth 2 s) :stale (nth 3 s)
                     :unreviewed (- (nth 1 s) (nth 2 s) (nth 3 s))
                     :ranges (legu--parse-ranges (nth 4 s)))
               rows))
    rows))

(ert-deftest legu-test-queue-ordering-strips-the-trailing-slash ()
  ;; "src" and "src-x" order differently from "src/" and "src-x/".
  (let* ((rows (legu-test--rows
                '(("src/a.clj" 10 0 0 "-")
                  ("src-x/b.clj" 10 0 0 "-")
                  ("a.clj" 10 0 0 "-")
                  ("src/api/c.clj" 10 0 0 "-"))))
         (queue (mapcar (lambda (r) (plist-get r :path)) (legu--queue rows 10))))
    ;; "src-x" sorts before "src/api" because ?- is below ?/ -- which is
    ;; only true because the key has no trailing slash.  This is the CLI's
    ;; own ordering; the integration test checks it against the binary.
    (should (equal queue '("a.clj" "src/a.clj" "src-x/b.clj" "src/api/c.clj")))))

(ert-deftest legu-test-queue-skips-finished-files-and-respects-the-limit ()
  (let ((rows (legu-test--rows '(("a" 10 10 0 "1-10")
                                 ("b" 10 0 0 "-")
                                 ("c" 10 5 5 "1-5")))))
    (should (equal (mapcar (lambda (r) (plist-get r :path)) (legu--queue rows 10))
                   '("b" "c")))
    (should (= 1 (length (legu--queue rows 1))))))

(ert-deftest legu-test-queue-todo-ranges-are-the-complement ()
  (let* ((rows (legu-test--rows '(("a" 10 4 0 "3-6"))))
         (row (car (legu--queue rows 10))))
    (should (equal (plist-get row :ranges) '((1 . 2) (7 . 10))))))


;;;; Snapshot trust

(ert-deftest legu-test-snapshot-trust-is-decided-by-mtime ()
  (let ((file (make-temp-file "legu-test")))
    (unwind-protect
        (progn
          (should-not (legu-snapshot-trusted-p nil file))
          (should-not (legu-snapshot-trusted-p
                       (list :started (time-subtract (current-time) 3600)) file))
          (should (legu-snapshot-trusted-p
                   (list :started (time-add (current-time) 3600)) file)))
      (delete-file file))))


;;;; Painting precedence

(defun legu-test--precedence (tier0 snap-reviewed snap-stale trusted)
  "Reproduce `legu--compute's arithmetic on explicit inputs."
  (let* ((reviewed (legu--ranges-union tier0 (and trusted snap-reviewed)))
         (stale (legu--ranges-subtract (and trusted snap-stale) reviewed)))
    (list :reviewed reviewed :stale stale)))

(ert-deftest legu-test-precedence-trusted-snapshot ()
  (let ((r (legu-test--precedence '((10 . 20)) '((10 . 20) (40 . 50)) '((15 . 25)) t)))
    (should (equal (plist-get r :reviewed) '((10 . 20) (40 . 50))))
    (should (equal (plist-get r :stale) '((21 . 25))))))

(ert-deftest legu-test-precedence-untrusted-snapshot-never-says-stale ()
  (let ((r (legu-test--precedence '((10 . 20)) '((10 . 20) (40 . 50)) '((15 . 25)) nil)))
    (should (equal (plist-get r :reviewed) '((10 . 20))))
    (should (equal (plist-get r :stale) nil))))


;;;; Overlays

(defmacro legu-test--with-buffer (lines &rest body)
  "Run BODY in a temp buffer of LINES numbered lines."
  (declare (indent 1))
  `(with-temp-buffer
     (dotimes (i ,lines) (insert (format "line %d\n" (1+ i))))
     (setq-local legu--overlays nil)
     ,@body))

(defun legu-test--legu-overlays ()
  "Every overlay this package painted in the current buffer."
  (seq-filter (lambda (o) (overlay-get o 'legu))
              (overlays-in (point-min) (point-max))))

(ert-deftest legu-test-paint-then-clear-leaves-nothing ()
  (legu-test--with-buffer 20
    (legu-overlay-paint :reviewed '((3 . 5)) :stale '((10 . 11)) :tickets '(3))
    (should (> (length (legu-test--legu-overlays)) 0))
    (legu-overlay-clear)
    (should (= 0 (length (legu-test--legu-overlays))))))

(ert-deftest legu-test-ticket-glyph-wins-the-line ()
  (legu-test--with-buffer 20
    (legu-overlay-paint :reviewed '((3 . 5)) :tickets '(3))
    (let ((states (mapcar (lambda (o) (overlay-get o 'legu-state))
                          (legu-test--legu-overlays))))
      (should (memq 'ticket states))
      ;; Exactly one overlay per line: 3 is the ticket, 4 and 5 reviewed.
      (should (= 3 (length states))))))

(ert-deftest legu-test-unverified-drops-the-alarm-background ()
  (legu-test--with-buffer 20
    (legu-overlay-paint :stale '((3 . 4)) :unverified t)
    (dolist (o (legu-test--legu-overlays))
      (should (eq 'unverified (overlay-get o 'legu-state)))
      (should-not (overlay-get o 'face)))))

(ert-deftest legu-test-deleting-the-text-evaporates-the-overlay ()
  (legu-test--with-buffer 20
    (legu-overlay-paint :reviewed '((3 . 4)))
    (let ((before (length (legu-test--legu-overlays))))
      (goto-char (point-min))
      (forward-line 2)
      (delete-region (point) (progn (forward-line 2) (point)))
      (should (< (length (legu-test--legu-overlays)) before)))))

(ert-deftest legu-test-typing-after-a-region-does-not-extend-it ()
  (legu-test--with-buffer 10
    (legu-overlay-paint :reviewed '((3 . 4)))
    (let* ((ov (seq-find (lambda (o) (eq 'reviewed (overlay-get o 'legu-state)))
                         (sort (legu-test--legu-overlays)
                               (lambda (a b) (> (overlay-start a) (overlay-start b))))))
           (end (overlay-end ov)))
      (goto-char end)
      (insert "intruder\n")
      (should (= end (overlay-end ov))))))

(ert-deftest legu-test-marks-do-not-travel-with-the-kill-ring ()
  ;; The reason this package uses overlays and not text properties.
  (legu-test--with-buffer 10
    (legu-overlay-paint :reviewed '((3 . 4)))
    (goto-char (point-min))
    (forward-line 2)
    (kill-region (point) (progn (forward-line 2) (point)))
    (with-temp-buffer
      (yank)
      (should-not (text-property-not-all (point-min) (point-max) 'legu-state nil)))))

(ert-deftest legu-test-dim-refaces-without-deleting ()
  (legu-test--with-buffer 10
    (legu-overlay-paint :reviewed '((3 . 4)) :stale '((6 . 6)))
    (let ((before (length (legu-test--legu-overlays))))
      (legu-overlay-dim)
      (should (= before (length (legu-test--legu-overlays))))
      (dolist (o (legu-test--legu-overlays))
        (should-not (overlay-get o 'face))))))

(ert-deftest legu-test-out-of-scope-paints-one-marker ()
  (legu-test--with-buffer 30
    (legu-overlay-paint :reviewed '((1 . 30)) :out-of-scope t)
    (let ((overlays (legu-test--legu-overlays)))
      (should (= 1 (length overlays)))
      (should (eq 'ignored (overlay-get (car overlays) 'legu-state))))))


;;;; Mode line

(ert-deftest legu-test-lighter-is-risky ()
  ;; Without this the lighter renders nothing at all, silently.
  (should (get 'legu-lighter 'risky-local-variable)))

(ert-deftest legu-test-lighter-states ()
  (with-temp-buffer
    (setq-local legu--root "/tmp/x/")
    (let ((legu--snapshots (make-hash-table :test #'equal)))
      ;; 618 of 1000: floor says 61, round would say 62.  The floor points
      ;; at remaining work, never away from it.
      (puthash "/tmp/x/" (list :coverage (list :lines 1000 :reviewed 618 :stale 20
                                               :never 362 :files 5))
               legu--snapshots)
      (setq-local legu--stale-count 3)
      (should (equal (substring-no-properties (legu--lighter)) " legu 61%▪3"))
      (setq-local legu--stale-count 0)
      (should (equal (substring-no-properties (legu--lighter)) " legu 61%"))
      (setq-local legu--unaccounted t)
      (should (equal (substring-no-properties (legu--lighter)) " legu 61%?"))
      (setq-local legu--unaccounted nil)
      (setq-local legu--unverified t)
      (should (equal (substring-no-properties (legu--lighter)) " legu?"))
      (setq-local legu--unverified nil)
      (setq-local legu--scope 'out)
      (should (equal (substring-no-properties (legu--lighter)) " legu —"))
      (setq-local legu--scope 'in)
      ;; A broken sidecar flags the store without taking the numbers away.
      (puthash "/tmp/x/" (list :coverage (list :lines 1000 :reviewed 618 :stale 20
                                               :never 362 :files 5)
                               :errors (list (list :file ".review/b.txt.jsonl"
                                                   :reason "not a review record")))
               legu--snapshots)
      (should (equal (substring-no-properties (legu--lighter)) " legu 61%!"))
      (puthash "/tmp/x/" (list :state 'error) legu--snapshots)
      (should (equal (substring-no-properties (legu--lighter)) " legu!")))))

(ert-deftest legu-test-list-banner-is-driven-by-errors ()
  (let ((legu--snapshots (make-hash-table :test #'equal)))
    (puthash "/tmp/x/"
             (list :state 'fresh :started (current-time)
                   :coverage (list :lines 10 :reviewed 5 :stale 0 :never 5 :files 1)
                   :errors (list (list :file ".review/b.txt.jsonl"
                                       :reason "not a review record")))
             legu--snapshots)
    (with-temp-buffer
      (legu-list-mode)
      (setq legu-list--root "/tmp/x/")
      (legu-list--render)
      (let ((text (substring-no-properties (buffer-string))))
        (should (string-match-p "\\.review/b\\.txt\\.jsonl" text))
        (should (string-match-p "not a review record" text))
        ;; The numbers next to it are this snapshot's, not the last good one's.
        (should (string-match-p "read +5" text))
        (should-not (string-match-p "last good snapshot" text))
        (should-not (string-match-p "every legu command is failing" text))))))

(ert-deftest legu-test-list-banner-prefers-a-snapshot-with-no-numbers ()
  ;; A snapshot that failed outright must not show the sidecar list a partial
  ;; one left behind: the numbers under it are nobody's.
  (let ((legu--snapshots (make-hash-table :test #'equal)))
    (puthash "/tmp/x/"
             (list :state 'error :started (current-time)
                   :error (list :kind 'cli-failed :message "legu: git not found")
                   :errors (list (list :file ".review/b.txt.jsonl" :reason "stale")))
             legu--snapshots)
    (with-temp-buffer
      (legu-list-mode)
      (setq legu-list--root "/tmp/x/")
      (legu-list--render)
      (let ((text (substring-no-properties (buffer-string))))
        (should (string-match-p "every legu command is failing" text))
        (should (string-match-p "git not found" text))
        (should-not (string-match-p "b\\.txt\\.jsonl" text))))))


(ert-deftest legu-test-list-render-survives-fontification ()
  ;; compilation-mode's font-lock strips `face'.  The heading, the counts and
  ;; the anchors must still read after it has run, and the anchor must still
  ;; be a compilation message.
  (let ((legu--snapshots (make-hash-table :test #'equal)))
    (puthash "/tmp/x/"
             (list :state 'fresh :started (current-time)
                   :coverage (list :lines 100 :reviewed 10 :stale 1 :never 89 :files 2)
                   :queue (list (list :path "a.el" :unreviewed 13 :stale 0
                                      :ranges '((1 . 13)))))
             legu--snapshots)
    (with-temp-buffer
      (legu-list-mode)
      (setq legu-list--root "/tmp/x/")
      (legu-list--render)
      (font-lock-ensure)
      (goto-char (point-min))
      (should (eq 'legu-list-heading (get-text-property (point) 'font-lock-face)))
      (search-forward "a.el")
      (should (get-text-property (point) 'compilation-message))
      (should (memq 'legu-list-path (ensure-list (get-text-property (1- (point)) 'font-lock-face))))
      (should (memq 'legu-list-anchor (ensure-list (get-text-property (point) 'font-lock-face)))))))

(ert-deftest legu-test-list-columns-line-up-and-zeros-are-dim ()
  (let ((legu--snapshots (make-hash-table :test #'equal))
        (rows (make-hash-table :test #'equal)))
    (dotimes (i 5) (puthash (format "f%d" i) (list :unreviewed 1 :stale 0) rows))
    (puthash "/tmp/x/"
             (list :state 'fresh :started (current-time)
                   :coverage (list :lines 100 :reviewed 10 :stale 1 :never 89 :files 2)
                   :rows rows
                   :queue (list (list :path "a.el" :unreviewed 13 :stale 0 :ranges '((1 . 13)))
                                (list :path "deep/er/path/to/some/file.el"
                                      :unreviewed 4 :stale 2 :ranges '((1 . 4)))))
             legu--snapshots)
    (with-temp-buffer
      (legu-list-mode)
      (setq legu-list--root "/tmp/x/")
      (legu-list--render)
      (should (string-match-p "NEXT  2 of 5 files" (buffer-string)))
      ;; Both count columns start at the same screen column.
      (should (= (progn (goto-char (point-min)) (search-forward "13 unread") (current-column))
                 (progn (goto-char (point-min)) (search-forward " 4 unread") (current-column))))
      (goto-char (point-min))
      (search-forward "0 stale")
      (should (eq 'legu-list-count (get-text-property (1- (point)) 'face)))
      (search-forward "2 stale")
      (should (eq 'legu-stale (get-text-property (1- (point)) 'face))))))

(defun legu-test--column-of (needle)
  "The screen column NEEDLE starts at, counting an elision as one glyph."
  (goto-char (point-min))
  (search-forward needle)
  (legu-list--display-width
   (buffer-substring (line-beginning-position) (match-beginning 0))))

(ert-deftest legu-test-list-elides-the-middle-of-a-long-path ()
  (let* ((path ".tickets/archive/lgu-01m237878ry2--give-legu-a-human-output.md")
         (shown (legu-list--elide path 30))
         (hidden (text-property-not-all 0 (length shown) 'display nil shown)))
    (should (<= (legu-list--display-width shown) 30))
    ;; The whole path is still there to be copied, visited and parsed.
    (should (equal path (substring-no-properties shown)))
    ;; Both ends survive: the directory it sits in, and the end of the name
    ;; that tells it apart from its neighbours.
    (should hidden)
    (should (> hidden 0))
    (should (equal "…" (substring-no-properties
                        (get-text-property hidden 'display shown))))
    (should-not (get-text-property (1- (length shown)) 'display shown))))

(ert-deftest legu-test-list-leaves-a-path-that-fits-alone ()
  (let ((shown (legu-list--elide "src/legu.el" 30)))
    (should (equal "src/legu.el" (substring-no-properties shown)))
    (should (= 11 (legu-list--display-width shown)))
    (should-not (text-property-not-all 0 (length shown) 'display nil shown))))

(ert-deftest legu-test-list-columns-line-up-past-a-long-path ()
  ;; A path too long for the anchor column must not push the counts off the
  ;; row it is on, and must still parse as a compilation message.
  (let ((legu--snapshots (make-hash-table :test #'equal))
        (long (concat ".tickets/archive/"
                      "lgu-01m237878ry2--give-legu-next-and-legu-coverage-"
                      "a-human-output.md")))
    (puthash "/tmp/x/"
             (list :state 'fresh :started (current-time)
                   :coverage (list :lines 100 :reviewed 10 :stale 1 :never 89 :files 2)
                   :queue (list (list :path "a.el" :unreviewed 13 :stale 0
                                      :ranges '((1 . 13)))
                                (list :path long :unreviewed 44 :stale 0
                                      :ranges '((1 . 44)))))
             legu--snapshots)
    (with-temp-buffer
      (legu-list-mode)
      (setq legu-list--root "/tmp/x/")
      (legu-list--render)
      (should (= (legu-test--column-of "13 unread")
                 (legu-test--column-of "44 unread")))
      ;; next-error still has the whole anchor to work from.
      (should (string-match-p (regexp-quote (concat long ":1:44:"))
                              (substring-no-properties (buffer-string))))
      (goto-char (point-min))
      (search-forward long)
      (should (text-property-not-all (line-beginning-position) (point)
                                     'display nil))
      (should (equal long (get-text-property (1- (point)) 'legu-path)))
      (font-lock-ensure)
      (should (get-text-property (point) 'compilation-message)))))

(ert-deftest legu-test-list-says-when-there-is-nothing-to-read ()
  (let ((legu--snapshots (make-hash-table :test #'equal)))
    (puthash "/tmp/x/"
             (list :state 'fresh :started (current-time)
                   :coverage (list :lines 10 :reviewed 10 :stale 0 :never 0 :files 1))
             legu--snapshots)
    (with-temp-buffer
      (legu-list-mode)
      (setq legu-list--root "/tmp/x/")
      (legu-list--render)
      (should (string-match-p "nothing to read" (buffer-string)))
      (setq legu-list--filter 'stale)
      (legu-list--render)
      (should (string-match-p "no stale regions" (buffer-string)))
      (should (string-match-p "stale only" (buffer-string))))))

(ert-deftest legu-test-list-percent-never-rounds-a-few-lines-away ()
  (should (equal " <0.1%" (legu-list--percent 0.0001)))
  (should (equal ">99.9%" (legu-list--percent 0.9999)))
  (should (equal "  0.0%" (legu-list--percent 0)))
  (should (equal "100.0%" (legu-list--percent 1))))


;;;; JSON edge cases

(ert-deftest legu-test-json-null-and-false-are-nil ()
  (let ((data (legu--parse-json
               "{\"stale\":[{\"path\":\"a\",\"start\":null,\"end\":null,\"state\":\"stale\"},
                            {\"path\":\"b\",\"state\":\"missing\"}],\"flag\":false}")))
    (should data)
    (should-not (alist-get 'flag data))
    (let ((entries (alist-get 'stale data)))
      (should-not (alist-get 'start (nth 0 entries)))
      (should-not (assq 'start (nth 1 entries)))
      (should (equal "missing" (alist-get 'state (nth 1 entries)))))))

(ert-deftest legu-test-json-malformed-returns-nil ()
  (should-not (legu--parse-json "{\"files\":"))
  (should-not (legu--parse-json "legu: no such file: x")))


;;;; Frontier guards

(ert-deftest legu-test-marking-backwards-is-refused ()
  (legu-test--with-buffer 40
    (setq-local legu--frontier (copy-marker (legu--line-position 20) t))
    (goto-char (legu--line-position 5))
    (should-error (legu--target-region nil) :type 'user-error)))

(ert-deftest legu-test-frontier-span-is-what-you-just-read ()
  (legu-test--with-buffer 40
    (setq-local legu--frontier (copy-marker (legu--line-position 10) t))
    (goto-char (legu--line-position 25))
    (should (equal (legu--target-region nil) '(10 . 25)))))

(ert-deftest legu-test-region-ending-at-column-zero-excludes-that-line ()
  (legu-test--with-buffer 40
    (goto-char (legu--line-position 3))
    (push-mark (point) t t)
    (goto-char (legu--line-position 8))
    (activate-mark)
    (should (equal (legu--target-region nil) '(3 . 7)))
    (goto-char (1+ (legu--line-position 8)))
    (should (equal (legu--target-region nil) '(3 . 8)))
    (deactivate-mark)))

(ert-deftest legu-test-target-string ()
  (should (equal (legu--target-string "a.txt" '(3 . 9)) "a.txt:3-9"))
  (should (equal (legu--target-string "a.txt" nil) "a.txt")))


;;;; The write queue

(ert-deftest legu-test-writes-are-serialized-per-root ()
  (let ((legu--write-queues (make-hash-table :test #'equal))
        (legu--write-active (make-hash-table :test #'equal))
        (started nil) (finish nil))
    (cl-letf (((symbol-function 'legu--run)
               (lambda (_root args callback)
                 (push (car (last args)) started)
                 (push (lambda () (funcall callback 'ok "" "")) finish)))
              ((symbol-function 'legu-refresh-snapshot) #'ignore))
      (legu--enqueue-write "/r/" '("mark" "a") #'ignore)
      (legu--enqueue-write "/r/" '("mark" "b") #'ignore)
      ;; Only the first has been handed to a process.
      (should (equal started '("a")))
      (funcall (pop finish))
      (should (equal (reverse started) '("a" "b"))))))


;;;; The version handshake

(defmacro legu-test--with-version-answer (answer &rest body)
  "Run BODY with `legu--run' answering the version handshake with ANSWER.
ANSWER is (STATUS STDOUT).  Binds `calls' to the argument lists seen and
`messages' to what the handshake said, newest first."
  (declare (indent 1))
  `(let ((legu--version-checked nil) calls messages)
     (cl-letf (((symbol-function 'legu--run)
                (lambda (_root args callback)
                  (push args calls)
                  (funcall callback (nth 0 ,answer) (nth 1 ,answer) "")))
               ((symbol-function 'message)
                (lambda (fmt &rest args) (push (apply #'format fmt args) messages))))
       ,@body)))

(ert-deftest legu-test-version-handshake-is-asked-once-per-root ()
  (legu-test--with-version-answer
      (list 'ok (format "{\"version\":\"%s\",\"schema\":%d}"
                        legu-cli-minimum-version legu-sidecar-schema))
    (legu--check-version "/r/")
    (legu--check-version "/r/")
    (should (equal calls '(("--version" "--json"))))
    (should-not messages)))

(ert-deftest legu-test-version-handshake-happens-on-the-first-cli-run ()
  "Any CLI run asks, not just the snapshot -- and asks once."
  (let ((legu--version-checked nil) messages)
    (cl-letf (((symbol-function 'legu--program) (lambda () "/bin/true"))
              ((symbol-function 'message)
               (lambda (fmt &rest args) (push (apply #'format fmt args) messages))))
      (legu--run default-directory '("status" "--json") #'ignore)
      (legu--run default-directory '("stale" "--json") #'ignore)
      (legu-test--wait (lambda () messages) 5)
      ;; /bin/true names no version, which is what an old legu looks like.
      (should (= 1 (length messages)))
      (should (string-match-p "names no version" (car messages))))))

(ert-deftest legu-test-version-handshake-names-a-cli-too-old-to-answer ()
  (legu-test--with-version-answer (list 'failed "")
    (legu--check-version "/r/")
    (should (= 1 (length messages)))
    (should (string-match-p (regexp-quote legu-cli-minimum-version) (car messages)))))

(ert-deftest legu-test-version-handshake-names-a-cli-older-than-we-speak ()
  (legu-test--with-version-answer
      (list 'ok (format "{\"version\":\"0.0.1\",\"schema\":%d}" legu-sidecar-schema))
    (legu--check-version "/r/")
    (should (= 1 (length messages)))
    (should (string-match-p "0\\.0\\.1" (car messages)))
    (should (string-match-p (regexp-quote legu-cli-minimum-version) (car messages)))))

(ert-deftest legu-test-version-handshake-names-a-store-schema-we-do-not-read ()
  (legu-test--with-version-answer
      (list 'ok (format "{\"version\":\"99.0.0\",\"schema\":%d}"
                        (1+ legu-sidecar-schema)))
    (legu--check-version "/r/")
    (should (= 1 (length messages)))
    (should (string-match-p (format "schema %d" (1+ legu-sidecar-schema))
                            (car messages)))))


;;;; Integration: the real binary against a real repository

(defmacro legu-test--with-repo (files &rest body)
  "Create a git repository containing FILES, then run BODY with `root' bound.
FILES is a list of (RELPATH . CONTENT).  Skips unless legu is installed."
  (declare (indent 1))
  `(progn
     (unless (legu-test--binary-p) (ert-skip "the legu CLI is not installed"))
     (let* ((root (file-name-as-directory (make-temp-file "legu-repo" t)))
            (default-directory root)
            (legu--snapshots (make-hash-table :test #'equal))
            (legu--generations (make-hash-table :test #'equal))
            (legu--write-queues (make-hash-table :test #'equal))
            (legu--write-active (make-hash-table :test #'equal))
            (legu--root-cheap-cache (make-hash-table :test #'equal))
            (legu--warned-paths nil)
            (legu--version-checked nil)
            (legu--failures nil))
       (unwind-protect
           (progn
             (legu-test--git "init" "-q")
             (legu-test--git "config" "user.name" "tester")
             (legu-test--git "config" "user.email" "tester@example.invalid")
             (dolist (f ,files)
               (let ((path (expand-file-name (car f) root))
                     (coding-system-for-write 'binary))
                 (make-directory (file-name-directory path) t)
                 (with-temp-file path
                   (set-buffer-multibyte nil)
                   (insert (cdr f)))))
             (legu-test--git "add" "-A")
             (legu-test--git "commit" "-qm" "init")
             ,@body)
         ;; A repo deleted while legu is still writing to it crashes the CLI
         ;; and lands the failure in whichever test is running next.
         (legu-test--wait (lambda () (and (not (gethash root legu--write-active))
                                          (not (gethash root legu--write-queues))))
                          10)
         (dolist (buffer (buffer-list))
           (when (and (buffer-file-name buffer)
                      (string-prefix-p root (buffer-file-name buffer)))
             (with-current-buffer buffer (set-buffer-modified-p nil))
             (kill-buffer buffer)))
         ;; Neither table is let-bound above, so a debounce timer or a store
         ;; watcher armed here outlives the directory it points at and fires
         ;; into whichever test is running by then.  The watchers go first: a
         ;; watch still live re-arms the timer the moment anything pumps.
         (dolist (entry (gethash root legu--watchers))
           (ignore-errors (file-notify-rm-watch (cdr entry))))
         (remhash root legu--watchers)
         (when-let* ((timer (gethash root legu--refresh-timers)))
           (cancel-timer timer))
         (remhash root legu--refresh-timers)
         (delete-directory root t)))))

(defun legu-test--git (&rest args)
  "Run git with ARGS in `default-directory'."
  (apply #'call-process "git" nil nil nil args))

(defun legu-test--legu (&rest args)
  "Run legu with ARGS synchronously.  Returns (EXIT STDOUT STDERR)."
  (let ((err (make-temp-file "legu-err"))
        (out (generate-new-buffer " *legu-test-out*")))
    (unwind-protect
        (let* ((exit (apply #'call-process (legu--program) nil (list out err) nil args))
               (stdout (with-current-buffer out (buffer-string)))
               (stderr (with-temp-buffer (insert-file-contents err) (buffer-string))))
          (list exit stdout stderr))
      (kill-buffer out)
      (delete-file err))))

(defun legu-test--wait (predicate &optional seconds)
  "Pump the event loop until PREDICATE returns non-nil, or SECONDS elapse."
  (let ((deadline (time-add (current-time) (or seconds 30))))
    (while (and (not (funcall predicate))
                (time-less-p (current-time) deadline))
      (accept-process-output nil 0.05)
      (sit-for 0.01))
    (funcall predicate)))

(defun legu-test--lines (n)
  "N numbered lines of text."
  (mapconcat (lambda (i) (format "line %d" i)) (number-sequence 1 n) "\n"))

(ert-deftest legu-test-integration-a-finished-repo-leaves-nothing-armed ()
  "A scratch repo's debounce timer and store watchers die with its directory.
One that outlives it fires into a directory that is gone, and Emacs
reports that through `message' -- inside whichever test is running by
then, which is how this suite acquired a flake."
  (let (finished)
    (legu-test--with-repo '(("a.txt" . "one\ntwo\n"))
      (setq finished root)
      (make-directory (expand-file-name ".review" root))
      (legu--watch-store root)
      (legu-refresh-snapshot root 30))
    (should-not (gethash finished legu--refresh-timers))
    (should-not (gethash finished legu--watchers))))

(ert-deftest legu-test-integration-file-hash-matches-the-cli ()
  "The single test that catches upstream drift on the day it lands."
  (legu-test--with-repo
      (list (cons "a.txt" (concat "alpha\t \nbeta  \r\nlatin1: "
                                  (unibyte-string #xe9) "\nomega\n"))
            (cons "nonewline.txt" "no trailing newline")
            (cons "tiny.txt" "x"))
    (dolist (file '("a.txt" "nonewline.txt" "tiny.txt"))
      (legu-test--legu "mark" file)
      (let* ((records (legu-sidecar-records root file))
             (record (car (plist-get records :regions))))
        (should record)
        (should (equal (legu--file-hash (expand-file-name file root))
                       (alist-get 'file-hash record)))))))

(ert-deftest legu-test-integration-a-cr-ending-a-line-stays-out-of-its-hash ()
  "Pin the content hashes the CLI records for lines ending in CR.
The values were observed from the CLI; `lines-of' in the CLI says why a
CR before a final NEL goes too.  A change that moves any of them turns
every record over such a line stale."
  (legu-test--with-repo
      (list (cons "a.txt" (concat "crlf\r\n"
                                  "nel" (unibyte-string 13 #x85) "\n"
                                  "crcr\r\r\n"
                                  "plain\n")))
    (dolist (line '(1 2 3 4))
      (legu-test--legu "mark" (format "a.txt:%d-%d" line line)))
    (should (equal (mapcar (lambda (record) (alist-get 'content-hash record))
                           (plist-get (legu-sidecar-records root "a.txt") :regions))
                   '("c613dc516f3260b7b0cd688c74447e4024a1bf958ad25ae2d543d04923f84194"
                     "5d130d74b91ba83dc3a4a4802b0167550b8ad88406b33c1a702b9af3d113e11e"
                     "1ee0bcebb5042f8ce63846fdccf46b2295c79453bf50e20c5ecdbaa5d24ca3a1"
                     "a116c9ed46d6207734a43317d30fd88f52ac8634c37d904bbf4e41d865f90475")))))

(ert-deftest legu-test-integration-a-nul-counts-only-in-the-first-8000-bytes ()
  (legu-test--with-repo
      (list (cons "inside.bin" (concat (make-string 7999 ?a) (unibyte-string 0) "\n"))
            (cons "outside.txt" (concat (make-string 8000 ?a) (unibyte-string 0) "\n")))
    (legu-test--legu "mark" "inside.bin")
    (legu-test--legu "mark" "outside.txt")
    (let ((record (lambda (path)
                    (car (plist-get (legu-sidecar-records root path) :regions)))))
      (should (alist-get 'opaque (funcall record "inside.bin")))
      (should-not (alist-get 'opaque (funcall record "outside.txt")))
      (should (alist-get 'content-hash (funcall record "outside.txt"))))))

(ert-deftest legu-test-integration-tier0-paints-without-a-subprocess ()
  (legu-test--with-repo (list (cons "a.txt" (concat (legu-test--lines 40) "\n")))
    (legu-test--legu "mark" "a.txt:10-20")
    (let ((tier0 (legu--tier0 root "a.txt" (expand-file-name "a.txt" root))))
      (should (equal (plist-get tier0 :reviewed) '((10 . 20))))
      (should-not (plist-get tier0 :unresolved)))
    ;; Edit inside the region: tier 0 must say nothing, never "stale".
    (with-temp-file (expand-file-name "a.txt" root)
      (insert (concat (legu-test--lines 40) "\n"))
      (goto-char (point-min))
      (forward-line 14)
      (insert "changed\n"))
    (let ((tier0 (legu--tier0 root "a.txt" (expand-file-name "a.txt" root))))
      (should-not (plist-get tier0 :reviewed))
      (should (plist-get tier0 :unresolved)))))

(ert-deftest legu-test-integration-one-file-changing-does-not-blind-the-others ()
  (legu-test--with-repo (list (cons "a.txt" (concat (legu-test--lines 20) "\n"))
                              (cons "b.txt" (concat (legu-test--lines 20) "\n")))
    (legu-test--legu "mark" "a.txt:1-5")
    (legu-test--legu "mark" "b.txt:1-5")
    (with-temp-file (expand-file-name "b.txt" root) (insert "rewritten\n"))
    (should (equal '((1 . 5)) (plist-get (legu--tier0 root "a.txt"
                                                      (expand-file-name "a.txt" root))
                                         :reviewed)))
    (should-not (plist-get (legu--tier0 root "b.txt" (expand-file-name "b.txt" root))
                           :reviewed))))

(ert-deftest legu-test-integration-derived-numbers-match-the-cli ()
  "This is what licenses never invoking `coverage' or `next'."
  (legu-test--with-repo (list (cons "src/a.txt" (concat (legu-test--lines 40) "\n"))
                              (cons "src/b.txt" (concat (legu-test--lines 30) "\n"))
                              (cons "c.txt" (concat (legu-test--lines 10) "\n")))
    (legu-test--legu "mark" "src/a.txt:1-20")
    (legu-test--legu "mark" "src/b.txt")
    (with-temp-file (expand-file-name "src/a.txt" root)
      (insert (concat (legu-test--lines 40) "\n"))
      (goto-char (point-min))
      (forward-line 4)
      (insert "changed\n"))
    (legu-refresh-snapshot root)
    (should (legu-test--wait (lambda () (plist-get (legu-snapshot root) :coverage))))
    (let* ((mine (legu-coverage-numbers root))
           (theirs (legu--parse-json (nth 1 (legu-test--legu "coverage" "--json"))))
           (queue (plist-get (legu-snapshot root) :queue))
           (their-queue (alist-get 'next (legu--parse-json
                                          (nth 1 (legu-test--legu "next" "--json"
                                                                  "--limit" "50"))))))
      (should (= (plist-get mine :files) (alist-get 'eligible-files theirs)))
      (should (= (plist-get mine :lines) (alist-get 'eligible-lines theirs)))
      (should (= (plist-get mine :reviewed) (alist-get 'reviewed theirs)))
      (should (= (plist-get mine :stale) (alist-get 'stale theirs)))
      (should (= (plist-get mine :never) (alist-get 'unreviewed theirs)))
      (should (= (length queue) (length their-queue)))
      (cl-loop for row in queue
               for other in their-queue
               do (should (equal (plist-get row :path) (alist-get 'path other)))
               do (should (= (plist-get row :unreviewed) (alist-get 'unreviewed other)))
               do (should (= (plist-get row :stale) (alist-get 'stale other)))
               do (should (equal (legu-format-ranges (plist-get row :ranges))
                                 (alist-get 'ranges other)))))))

(ert-deftest legu-test-integration-overlapping-records-count-each-line-once ()
  "Records that overlap or touch count their shared lines once, a stale
record counts only where no reviewed one covers it, and the ranges
`status' and `next' print join records that touch."
  (legu-test--with-repo (list (cons "a.txt" (concat (legu-test--lines 20) "\n")))
    (legu-test--legu "mark" "a.txt:1-5")
    (legu-test--legu "mark" "a.txt:3-8")
    (legu-test--legu "mark" "a.txt:9-10")
    (legu-test--legu "mark" "a.txt:12-16")
    (with-temp-file (expand-file-name "a.txt" root)
      (insert (legu-test--lines 13) "\nchanged\n"
              (mapconcat (lambda (i) (format "line %d" i)) (number-sequence 15 20) "\n")
              "\n"))
    (legu-test--legu "mark" "a.txt:15-18")
    (let ((file (car (alist-get 'files (legu--parse-json
                                        (nth 1 (legu-test--legu "status" "--json"))))))
          (queued (car (alist-get 'next (legu--parse-json
                                         (nth 1 (legu-test--legu "next" "--json"))))))
          (coverage (legu--parse-json (nth 1 (legu-test--legu "coverage" "--json")))))
      (should (equal "a.txt" (alist-get 'path file)))
      (should (= 14 (alist-get 'reviewed file)))
      (should (= 3 (alist-get 'stale file)))
      (should (= 3 (alist-get 'unreviewed file)))
      (should (equal "1-10,15-18" (alist-get 'ranges file)))
      (should (equal "a.txt" (alist-get 'path queued)))
      (should (= 3 (alist-get 'stale queued)))
      (should (= 3 (alist-get 'unreviewed queued)))
      (should (equal "11-14,19-20" (alist-get 'ranges queued)))
      (should (= 20 (alist-get 'eligible-lines coverage)))
      (should (= 14 (alist-get 'reviewed coverage)))
      (should (= 3 (alist-get 'stale coverage)))
      (should (= 3 (alist-get 'unreviewed coverage))))))

(ert-deftest legu-test-integration-warning-on-stderr-is-not-a-failure ()
  (legu-test--with-repo (list (cons "a.txt" "one\n"))
    (with-temp-file (expand-file-name "untracked.txt" root) (insert "hello\n"))
    (let ((result (legu-test--legu "mark" "untracked.txt")))
      (should (= 0 (nth 0 result)))
      (should (string-match-p "not tracked by git" (nth 2 result))))
    ;; The mark still landed.
    (should (plist-get (legu-sidecar-records root "untracked.txt") :regions))))

(ert-deftest legu-test-integration-out-of-scope-file-reports-empty ()
  (legu-test--with-repo (list (cons "a.txt" "one\n"))
    (let ((data (legu--parse-json (nth 1 (legu-test--legu "status" "b.txt" "--json")))))
      (should (null (alist-get 'files data))))))

(defun legu-test--break-sidecar (root path)
  "Overwrite PATH's sidecar under ROOT with an unmerged conflict."
  (with-temp-file (expand-file-name (concat ".review/" path ".jsonl") root)
    (insert "<<<<<<< HEAD\n{\"schema\":3}\n=======\nnonsense\n>>>>>>> other\n")))

(ert-deftest legu-test-integration-one-broken-sidecar-does-not-down-the-cli ()
  (legu-test--with-repo (list (cons "a.txt" (concat (legu-test--lines 10) "\n"))
                              (cons "b.txt" (concat (legu-test--lines 10) "\n")))
    (legu-test--legu "mark" "a.txt:1-5")
    (legu-test--legu "mark" "b.txt:1-5")
    ;; A clean store says nothing, so the key is absent rather than empty.
    (should-not (assq 'errors (legu--parse-json
                               (nth 1 (legu-test--legu "status" "--json")))))
    (legu-test--break-sidecar root "b.txt")
    ;; Every read command answers for everything else, and names the file.
    (dolist (command '("status" "stale" "next" "coverage"))
      (let ((result (legu-test--legu command "--json")))
        (should (= 0 (nth 0 result)))
        (should (legu--parse-json (nth 1 result)))
        (should (string-match-p "cannot read" (nth 2 result))))
      ;; The human renderer names it too.
      (should (string-match-p "cannot read" (nth 2 (legu-test--legu command)))))
    (let* ((data (legu--parse-json (nth 1 (legu-test--legu "status" "--json"))))
           (a (seq-find (lambda (f) (equal "a.txt" (alist-get 'path f)))
                        (alist-get 'files data)))
           (errors (alist-get 'errors data)))
      (should (= 5 (alist-get 'reviewed a)))
      ;; Its state is unknown, so it is left out rather than called unread --
      ;; otherwise `next' sends the reviewer back to a file already marked.
      (should-not (seq-find (lambda (f) (equal "b.txt" (alist-get 'path f)))
                            (alist-get 'files data)))
      ;; Root-relative, once per file however many times it was loaded.
      (should (equal '(".review/b.txt.jsonl")
                     (mapcar (lambda (e) (alist-get 'file e)) errors)))
      (should (stringp (alist-get 'reason (car errors)))))
    (let ((cov (legu--parse-json (nth 1 (legu-test--legu "coverage" "--json")))))
      (should (= 5 (alist-get 'reviewed cov)))
      (should (= 10 (alist-get 'eligible-lines cov))))
    (should-not (seq-find (lambda (f) (equal "b.txt" (alist-get 'path f)))
                          (alist-get 'next (legu--parse-json
                                            (nth 1 (legu-test--legu "next" "--json"))))))
    ;; The other file still paints from its own sidecar.
    (should (equal '((1 . 5))
                   (plist-get (legu--tier0 root "a.txt" (expand-file-name "a.txt" root))
                              :reviewed)))
    (should-not (plist-get (legu-sidecar-records root "b.txt") :ok))
    ;; And the package keeps every number live while flagging the file.
    (legu-refresh-snapshot root)
    (should (legu-test--wait
             (lambda () (plist-get (legu-snapshot root) :errors))))
    (should (eq 'fresh (plist-get (legu-snapshot root) :state)))
    (should (equal '(".review/b.txt.jsonl")
                   (mapcar (lambda (e) (plist-get e :file))
                           (plist-get (legu-snapshot root) :errors))))
    (should (= 5 (plist-get (legu-coverage-numbers root) :reviewed)))))

(ert-deftest legu-test-integration-a-write-to-a-broken-sidecar-is-refused ()
  ;; Skipping the file on a read loses nothing; skipping it on a write would
  ;; drop the state it still holds.
  (legu-test--with-repo (list (cons "a.txt" (concat (legu-test--lines 10) "\n"))
                              (cons "b.txt" (concat (legu-test--lines 10) "\n")))
    (legu-test--legu "mark" "a.txt:1-5")
    (legu-test--legu "mark" "b.txt:1-5")
    (legu-test--break-sidecar root "b.txt")
    (let* ((sidecar (expand-file-name ".review/b.txt.jsonl" root))
           (bytes (with-temp-buffer (insert-file-contents sidecar) (buffer-string))))
      (dolist (args '(("mark" "b.txt:6-8")
                      ("ticket" "b.txt:6-8" "T-1")
                      ("forget" "b.txt:1-5")))
        (let ((result (apply #'legu-test--legu args)))
          (should (/= 0 (nth 0 result)))
          (should (string-match-p "cannot read" (nth 2 result)))))
      ;; A write to another file lands, names the sidecar it skipped, and
      ;; leaves the broken one untouched.
      (let ((result (legu-test--legu "mark" "a.txt:6-8")))
        (should (= 0 (nth 0 result)))
        (should (string-match-p "cannot read" (nth 2 result))))
      (should (equal bytes (with-temp-buffer (insert-file-contents sidecar)
                                             (buffer-string)))))))

(ert-deftest legu-test-integration-awkward-paths-round-trip ()
  (legu-test--with-repo (list (cons "weird dir/spa ce'quote\"and:12-14.txt" "one\ntwo\n"))
    (let* ((path "weird dir/spa ce'quote\"and:12-14.txt")
           (result (legu-test--legu "mark" (concat path ":1-2"))))
      (should (= 0 (nth 0 result)))
      (should (plist-get (legu-sidecar-records root path) :regions)))))

(ert-deftest legu-test-integration-whitespace-only-edits-are-not-changes ()
  (legu-test--with-repo (list (cons "a.txt" "  alpha  \nbeta\t\ngamma\n"))
    (legu-test--legu "mark" "a.txt:1-3")
    (with-temp-file (expand-file-name "a.txt" root) (insert "alpha\nbeta\ngamma\n"))
    (let ((data (legu--parse-json (nth 1 (legu-test--legu "stale" "--json")))))
      (should (null (alist-get 'stale data))))))

(ert-deftest legu-test-integration-unsaved-buffer-is-refused ()
  (legu-test--with-repo (list (cons "a.txt" (concat (legu-test--lines 3) "\n")))
    (let ((buffer (find-file-noselect (expand-file-name "a.txt" root))))
      (unwind-protect
          (with-current-buffer buffer
            (legu-mode 1)
            (goto-char (point-max))
            (insert "line 4\nline 5\nline 6\n")
            (should (buffer-modified-p))
            (let ((legu-save-before-mark nil))
              (should-error (legu-mark) :type 'user-error))
            (should (buffer-modified-p))
            (let ((legu-save-before-mark t))
              (legu-set-frontier)
              (goto-char (point-max))
              (legu-mark)
              (should-not (buffer-modified-p))))
        (kill-buffer buffer)))))

(ert-deftest legu-test-integration-mark-through-the-package ()
  (legu-test--with-repo (list (cons "a.txt" (concat (legu-test--lines 30) "\n")))
    (let ((buffer (find-file-noselect (expand-file-name "a.txt" root))))
      (unwind-protect
          (with-current-buffer buffer
            (legu-mode 1)
            (goto-char (legu--line-position 12))
            (legu-mark)
            (should (legu-test--wait
                     (lambda () (plist-get (legu-sidecar-records root "a.txt") :regions))))
            (let ((record (car (plist-get (legu-sidecar-records root "a.txt") :regions))))
              (should (= 1 (alist-get 'start record)))
              (should (= 12 (alist-get 'end record))))
            ;; The frontier advanced to the line after what was just read.
            (should (= 13 (line-number-at-pos legu--frontier)))
            (legu--repaint)
            (should (equal '((1 . 12)) (plist-get legu--painted :reviewed))))
        (kill-buffer buffer)))))

(defun legu-test--regions (path)
  "Parsed output from `legu regions PATH --json'."
  (let ((result (legu-test--legu "regions" path "--json")))
    (should (= 0 (nth 0 result)))
    (legu--parse-json (nth 1 result))))

(ert-deftest legu-test-integration-regions-reports-current-anchors-and-provenance ()
  (legu-test--with-repo (list (cons "a.txt" (concat (legu-test--lines 30) "\n")))
    (legu-test--legu "mark" "a.txt:10-20" "--reviewer" "Ada")
    (legu-test--legu "mark" "a.txt:12-14" "--reviewer" "Bea")
    (legu-test--legu "ticket" "a.txt:13-16" "T-1")
    (let ((unchanged (car (alist-get 'regions (legu-test--regions "a.txt")))))
      (should (equal "reviewed" (alist-get 'state unchanged)))
      (should (= 10 (alist-get 'start unchanged)))
      (should-not (alist-get 'moved unchanged)))
    ;; Shift both overlapping records without changing either one's content.
    (with-temp-file (expand-file-name "a.txt" root)
      (insert "above\n" (legu-test--lines 30) "\n"))
    (let* ((data (legu-test--regions "a.txt"))
           (regions (alist-get 'regions data))
           (ticket (car (alist-get 'tickets data)))
           (outer (seq-find (lambda (r) (= 11 (alist-get 'start r))) regions))
           (inner (seq-find (lambda (r) (= 13 (alist-get 'start r))) regions)))
      (should (equal "a.txt" (alist-get 'path data)))
      (should (eq t (alist-get 'eligible data)))
      (should (eq t (alist-get 'complete data)))
      (should (equal "present" (alist-get 'condition data)))
      (should (= 31 (alist-get 'total data)))
      (should-not (alist-get 'opaque data))
      (should (= 2 (length regions)))
      (should (equal "reviewed" (alist-get 'state outer)))
      (should (equal "reviewed" (alist-get 'state inner)))
      (should (equal "a.txt" (alist-get 'path (alist-get 'original outer))))
      (should (= 10 (alist-get 'start (alist-get 'original outer))))
      (should (= 20 (alist-get 'end (alist-get 'original outer))))
      (should (equal "Ada" (alist-get 'reviewer (alist-get 'original outer))))
      (should (alist-get 'commit (alist-get 'original outer)))
      (should (alist-get 'timestamp (alist-get 'original outer)))
      (should (= 14 (alist-get 'start ticket)))
      (should (= 17 (alist-get 'end ticket)))
      (should (equal "T-1" (alist-get 'ticket ticket)))
      (should (equal "a.txt" (alist-get 'path (alist-get 'original ticket)))))))

(ert-deftest legu-test-integration-regions-follows-renames-not-copies ()
  (legu-test--with-repo (list (cons "a.txt" (concat (legu-test--lines 20) "\n")))
    (legu-test--legu "mark" "a.txt:5-10")
    (copy-file "a.txt" "copy.txt")
    (legu-test--git "add" "copy.txt")
    (should-not (alist-get 'regions (legu-test--regions "copy.txt")))
    (legu-test--git "reset" "-q" "copy.txt")
    (delete-file "copy.txt")
    (legu-test--git "mv" "a.txt" "renamed.txt")
    (let* ((data (legu-test--regions "renamed.txt"))
           (region (car (alist-get 'regions data))))
      (should (equal "reviewed" (alist-get 'state region)))
      (should (= 5 (alist-get 'start region)))
      (should (eq t (alist-get 'moved region)))
      (should (equal "a.txt" (alist-get 'path (alist-get 'original region)))))))

(ert-deftest legu-test-integration-a-record-older-than-its-file-stays-in-place ()
  "A file marked before its first commit cites a commit it is not in.
An edit below the region must not shift it."
  (legu-test--with-repo (list (cons "seed.txt" "seed\n"))
    (with-temp-file (expand-file-name "new.txt" root) (insert (legu-test--lines 20) "\n"))
    (legu-test--legu "mark" "new.txt:5-10")
    (legu-test--git "add" "new.txt")
    (legu-test--git "commit" "-qm" "add new.txt")
    (with-temp-file (expand-file-name "new.txt" root)
      (insert (legu-test--lines 20) "\nbelow\n"))
    (let ((region (car (alist-get 'regions (legu-test--regions "new.txt")))))
      (should (equal "reviewed" (alist-get 'state region)))
      (should (= 5 (alist-get 'start region)))
      (should-not (alist-get 'moved region)))))

(defun legu-test--same-lines (n)
  "N identical lines: a region shifted to the wrong place still hashes the
same, so only the diff can put it where it belongs."
  (apply #'concat (make-list n "same\n")))

(ert-deftest legu-test-integration-records-citing-different-commits-shift-by-their-own ()
  (legu-test--with-repo (list (cons "a.txt" (legu-test--same-lines 30)))
    (legu-test--legu "mark" "a.txt:5-8")
    (with-temp-file (expand-file-name "a.txt" root)
      (insert "top\n" (legu-test--same-lines 30)))
    (legu-test--git "commit" "-qam" "one line above")
    (legu-test--legu "mark" "a.txt:20-25")
    (with-temp-file (expand-file-name "a.txt" root)
      (insert "top2\ntop\n" (legu-test--same-lines 30)))
    (let ((starts (sort (mapcar (lambda (r) (alist-get 'start r))
                                (alist-get 'regions (legu-test--regions "a.txt")))
                        #'<)))
      (should (equal '(7 21) starts)))))

(ert-deftest legu-test-integration-a-quoted-path-keeps-its-hunks-to-itself ()
  "git quotes a non-ASCII path in a diff header.  Neither file may take
the other's hunks when one command anchors both."
  (legu-test--with-repo (list (cons "a.txt" (legu-test--same-lines 30))
                              (cons "bé.txt" (concat (legu-test--lines 20) "\n")))
    (legu-test--legu "mark" "a.txt:5-8")
    (legu-test--legu "mark" "bé.txt:5-10")
    (with-temp-file (expand-file-name "a.txt" root)
      (insert "top\n" (legu-test--same-lines 30)))
    (with-temp-file (expand-file-name "bé.txt" root)
      (insert "x\ny\nz\n" (legu-test--lines 20) "\n"))
    (let* ((files (alist-get 'files (legu--parse-json
                                     (nth 1 (legu-test--legu "status" "--json")))))
           (ranges (lambda (path)
                     (alist-get 'ranges (seq-find (lambda (f) (equal path (alist-get 'path f)))
                                                  files)))))
      (should (equal "6-9" (funcall ranges "a.txt")))
      (should (equal "8-13" (funcall ranges "bé.txt"))))))

(defun legu-test--numbered (from to)
  "Lines FROM to TO of `legu-test--lines', each ending in a newline."
  (mapconcat (lambda (i) (format "line %d\n" i)) (number-sequence from to) ""))

(ert-deftest legu-test-integration-a-region-cut-and-pasted-within-its-file-is-moved ()
  "Cut from lines 5-10 and pasted at the end: the diff says the region was
deleted, so only the search for its content finds it."
  (legu-test--with-repo (list (cons "a.txt" (legu-test--numbered 1 30)))
    (legu-test--legu "mark" "a.txt:5-10")
    (with-temp-file (expand-file-name "a.txt" root)
      (insert (legu-test--numbered 1 4) (legu-test--numbered 11 30)
              (legu-test--numbered 5 10)))
    (let ((region (car (alist-get 'regions (legu-test--regions "a.txt")))))
      (should (equal "reviewed" (alist-get 'state region)))
      (should (= 25 (alist-get 'start region)))
      (should (= 30 (alist-get 'end region)))
      (should (eq t (alist-get 'moved region)))
      (should (equal "block moved" (alist-get 'reason region))))))

(ert-deftest legu-test-integration-a-region-found-twice-now-is-stale ()
  (legu-test--with-repo (list (cons "a.txt" (legu-test--numbered 1 30)))
    (legu-test--legu "mark" "a.txt:5-10")
    (with-temp-file (expand-file-name "a.txt" root)
      (insert (legu-test--numbered 1 4) (legu-test--numbered 11 30)
              (legu-test--numbered 5 10) (legu-test--numbered 5 10)))
    (let ((region (car (alist-get 'regions (legu-test--regions "a.txt")))))
      (should (equal "stale" (alist-get 'state region)))
      (should (= 5 (alist-get 'start region)))
      (should (= 10 (alist-get 'end region))))))

(ert-deftest legu-test-integration-a-region-with-a-twin-at-review-time-is-stale ()
  "The region is rewritten and its twin survives.  The file now holds the
reviewed content once, but it held it twice when reviewed, so the twin is
no evidence that the region moved."
  (let ((block "block 1\nblock 2\nblock 3\nblock 4\nblock 5\nblock 6\n"))
    (legu-test--with-repo (list (cons "a.txt" (concat (legu-test--numbered 1 4) block
                                                      (legu-test--numbered 11 19) block
                                                      (legu-test--numbered 26 30))))
      (legu-test--legu "mark" "a.txt:5-10")
      (with-temp-file (expand-file-name "a.txt" root)
        (insert (legu-test--numbered 1 4)
                "block 1\nblock 2\nchanged\nblock 4\nblock 5\nblock 6\n"
                (legu-test--numbered 11 19) block (legu-test--numbered 26 30)))
      (let ((region (car (alist-get 'regions (legu-test--regions "a.txt")))))
        (should (equal "stale" (alist-get 'state region)))
        (should (= 5 (alist-get 'start region)))
        (should (= 10 (alist-get 'end region)))
        (should (equal "content changed" (alist-get 'reason region)))))))

(ert-deftest legu-test-integration-regions-distinguishes-stale-and-missing ()
  (legu-test--with-repo (list (cons "a.txt" (concat (legu-test--lines 20) "\n"))
                              (cons "gone.txt" "one\ntwo\n"))
    (legu-test--legu "mark" "a.txt:5-10")
    (legu-test--legu "mark" "gone.txt")
    (with-temp-file "a.txt" (insert "one\ntwo\nrewritten\n"))
    (delete-file "gone.txt")
    (let ((stale (car (alist-get 'regions (legu-test--regions "a.txt"))))
          (missing (legu-test--regions "gone.txt")))
      (should (equal "stale" (alist-get 'state stale)))
      (should (equal "content changed" (alist-get 'reason stale)))
      (should (equal "missing" (alist-get 'condition missing)))
      (should (= 0 (alist-get 'total missing)))
      (let ((record (car (alist-get 'regions missing))))
        (should (equal "missing" (alist-get 'state record)))
        (should-not (alist-get 'start record))
        (should (= 1 (alist-get 'start (alist-get 'original record))))))))

(ert-deftest legu-test-integration-regions-reports-an-unreadable-file ()
  (unless (file-exists-p "/proc/1/mem")
    (ert-skip "this platform has no reliably unreadable proc file"))
  (legu-test--with-repo (list (cons "locked" "one\ntwo\n"))
    (legu-test--legu "mark" "locked")
    (delete-file "locked")
    (make-symbolic-link "/proc/1/mem" "locked")
    (let* ((data (legu-test--regions "locked"))
           (record (car (alist-get 'regions data))))
      (should (equal "unreadable" (alist-get 'condition data)))
      (should (= 0 (alist-get 'total data)))
      (should (eq t (alist-get 'eligible data)))
      (should (equal "missing" (alist-get 'state record)))
      (should (equal "file is unreadable" (alist-get 'reason record)))
      (should-not (alist-get 'start record)))))

(ert-deftest legu-test-integration-regions-documents-opaque-and-excluded-files ()
  (legu-test--with-repo (list (cons "empty.txt" "")
                              (cons "binary.dat" (concat "a" (unibyte-string 0) "b"))
                              (cons "ignored.txt" "ignored\n"))
    (with-temp-file ".reviewignore" (insert "ignored.txt\n"))
    (legu-test--git "add" ".reviewignore")
    (legu-test--legu "mark" "empty.txt")
    (legu-test--legu "mark" "binary.dat")
    (legu-test--legu "mark" "ignored.txt")
    (with-temp-file "untracked.txt" (insert "untracked\n"))
    (legu-test--legu "mark" "untracked.txt")
    (dolist (path '("empty.txt" "binary.dat"))
      (let* ((data (legu-test--regions path))
             (region (car (alist-get 'regions data))))
        (should (eq t (alist-get 'opaque data)))
        (should (= 1 (alist-get 'total data)))
        (should-not (alist-get 'start region))
        (should-not (alist-get 'end region))
        (should (equal "reviewed" (alist-get 'state region)))))
    (let ((ignored (legu-test--regions "ignored.txt"))
          (untracked (legu-test--regions "untracked.txt")))
      (should-not (alist-get 'eligible ignored))
      (should (equal "excluded by .reviewignore" (alist-get 'exclusion-reason ignored)))
      (should-not (alist-get 'eligible untracked))
      (should (equal "not tracked by git" (alist-get 'exclusion-reason untracked))))))

(ert-deftest legu-test-integration-regions-makes-sidecar-errors-explicit ()
  (legu-test--with-repo (list (cons "a.txt" "one\ntwo\n"))
    (legu-test--legu "mark" "a.txt")
    (legu-test--break-sidecar root "a.txt")
    (let* ((result (legu-test--legu "regions" "a.txt" "--json"))
           (data (legu--parse-json (nth 1 result))))
      (should (= 0 (nth 0 result)))
      (should-not (alist-get 'complete data))
      (should-not (alist-get 'regions data))
      (should (equal ".review/a.txt.jsonl"
                     (alist-get 'file (car (alist-get 'errors data)))))
      (should (string-match-p "cannot read" (nth 2 result))))
    (let ((human (legu-test--legu "regions" "a.txt")))
      (should (= 0 (nth 0 human)))
      (should (string-match-p "incomplete" (nth 1 human)))
      (should (string-match-p "cannot read" (nth 2 human))))))

(ert-deftest legu-test-integration-regions-human-output-and-invalid-targets ()
  (legu-test--with-repo (list (cons "a.txt" "one\ntwo\n"))
    (legu-test--legu "mark" "a.txt")
    (legu-test--legu "ticket" "a.txt:1" "T-1")
    (let ((human (legu-test--legu "regions" "a.txt")))
      (should (= 0 (nth 0 human)))
      (should (string-match-p "a.txt:1-2" (nth 1 human)))
      (should (string-match-p "reviewed" (nth 1 human)))
      (should (string-match-p "T-1" (nth 1 human)))
      (should (string-match-p "recorded a.txt:1" (nth 1 human)))
      (should (string-match-p "anchored .* at [0-9a-f]+" (nth 1 human))))
    (dolist (path '("." "no-such-file.txt" "../outside.txt"))
      (let ((result (legu-test--legu "regions" path "--json")))
        (should (/= 0 (nth 0 result)))
        (should-not (string-empty-p (nth 2 result)))))))

(ert-deftest legu-test-describe-region-uses-current-cli-anchors-and-rejects-old-answers ()
  (with-temp-buffer
    (insert (legu-test--lines 20))
    (setq buffer-file-name "/r/a.txt"
          legu--root "/r/"
          legu--relpath "a.txt")
    (set-buffer-modified-p nil)
    (goto-char (legu--line-position 8))
    (let (callbacks messages)
      (cl-letf (((symbol-function 'legu--run)
                 (lambda (_root args callback)
                   (should (equal args '("regions" "a.txt" "--json")))
                   (push callback callbacks)))
                ((symbol-function 'message)
                 (lambda (fmt &rest args) (push (apply #'format fmt args) messages))))
        (legu-describe-region)
        (legu-describe-region)
        ;; The older request finishes after a newer one exists and is ignored.
        (funcall (cadr callbacks) 'ok
                 "{\"path\":\"a.txt\",\"regions\":[],\"tickets\":[],\"complete\":true}" "")
        (should-not messages)
        (funcall (car callbacks) 'ok
                 "{\"path\":\"a.txt\",\"regions\":[{\"start\":5,\"end\":10,\"state\":\"stale\",\"reason\":\"content changed\",\"original\":{\"path\":\"old.txt\",\"start\":4,\"end\":9,\"commit\":\"abcdef012345\",\"reviewer\":\"Ada\",\"timestamp\":\"2026-08-28T10:00:00Z\"}},{\"start\":7,\"end\":8,\"state\":\"reviewed\",\"reason\":null,\"original\":{\"path\":\"a.txt\",\"start\":7,\"end\":8,\"commit\":\"123456789abc\",\"reviewer\":\"Bea\",\"timestamp\":\"2026-08-29T10:00:00Z\"}}],\"tickets\":[{\"start\":8,\"end\":9,\"ticket\":\"T-1\"}],\"complete\":true}" "")
        (should (= 1 (length messages)))
        (should (string-match-p "old.txt:4-9" (car messages)))
        (should (string-match-p "a.txt:7-8" (car messages)))
        (should (string-match-p "content changed" (car messages)))
        (should (string-match-p "T-1" (car messages)))))))

(ert-deftest legu-test-describe-region-rejects-answer-after-buffer-edit ()
  (with-temp-buffer
    (insert "one\ntwo\n")
    (setq buffer-file-name "/r/a.txt" legu--root "/r/" legu--relpath "a.txt")
    (let (callback messages)
      (cl-letf (((symbol-function 'legu--run)
                 (lambda (_root _args cb) (setq callback cb)))
                ((symbol-function 'message)
                 (lambda (fmt &rest args) (push (apply #'format fmt args) messages))))
        (set-buffer-modified-p nil)
        (legu-describe-region)
        (goto-char (point-max))
        (insert "three\n")
        (funcall callback 'ok
                 "{\"path\":\"a.txt\",\"regions\":[],\"tickets\":[],\"complete\":true}" "")
        (should-not messages)))))

(ert-deftest legu-test-integration-cli-version-is-one-we-speak ()
  "The handshake: the installed CLI names a version and the schema it writes."
  (unless (legu-test--binary-p) (ert-skip "the legu CLI is not installed"))
  (let ((plain (legu-test--legu "--version")))
    (should (= 0 (nth 0 plain)))
    (should (string-match-p "\\`legu [0-9][^ ]* (store schema [0-9]+)"
                            (nth 1 plain))))
  (let* ((result (legu-test--legu "--version" "--json"))
         (data (legu--parse-json (nth 1 result))))
    (should (= 0 (nth 0 result)))
    (should (stringp (alist-get 'version data)))
    (should-not (version< (alist-get 'version data) legu-cli-minimum-version))
    (should (eql legu-sidecar-schema (alist-get 'schema data)))))


;;;; The per-file regions query
;;
;; Tier 0.5: one `legu regions' for the file in front of you, when the
;; sidecar at its current path cannot account for it and no trusted
;; snapshot already has.

(defconst legu-test--rename-answer "\
{\"path\":\"b.txt\",\"eligible\":true,\"condition\":\"present\",\"total\":20,
 \"opaque\":false,\"complete\":true,
 \"regions\":[{\"start\":1,\"end\":10,\"state\":\"reviewed\",\"reason\":null,\"moved\":true,
               \"original\":{\"path\":\"a.txt\",\"start\":1,\"end\":10}},
              {\"start\":14,\"end\":16,\"state\":\"stale\",\"reason\":\"content changed\",
               \"original\":{\"path\":\"a.txt\",\"start\":14,\"end\":16}},
              {\"start\":null,\"end\":null,\"state\":\"missing\",\"reason\":\"file is gone\",
               \"original\":{\"path\":\"a.txt\",\"start\":30,\"end\":31}}],
 \"tickets\":[{\"start\":4,\"end\":6,\"ticket\":\"T-1\",\"state\":\"reviewed\"}]}"
  "A per-file answer carrying one reviewed, one stale and one missing record.")

(defmacro legu-test--with-file (lines &rest body)
  "Run BODY in a buffer visiting a real file of LINES lines under `root'.
`legu--root' and `legu--relpath' are set by hand, so nothing here needs
git, the CLI or `legu-mode'."
  (declare (indent 1))
  `(let* ((root (file-name-as-directory (make-temp-file "legu-file" t)))
          (file (expand-file-name "b.txt" root))
          (legu--snapshots (make-hash-table :test #'equal)))
     (with-temp-file file (insert (legu-test--lines ,lines) "\n"))
     (let ((buffer (find-file-noselect file)))
       (unwind-protect
           (with-current-buffer buffer
             (setq legu--root root legu--relpath "b.txt")
             ,@body)
         (with-current-buffer buffer (set-buffer-modified-p nil))
         (kill-buffer buffer)
         (delete-directory root t)))))

(ert-deftest legu-test-per-file-answer-splits-reviewed-from-stale ()
  (let ((parsed (legu--file-regions-parse
                 (legu--parse-json legu-test--rename-answer))))
    (should (equal (plist-get parsed :reviewed) '((1 . 10))))
    (should (equal (plist-get parsed :stale) '((14 . 16))))
    (should (equal (plist-get parsed :tickets) '(4)))
    (should (plist-get parsed :complete))))

(ert-deftest legu-test-per-file-answer-is-painted-under-the-sidecar ()
  (legu-test--with-file 20
    (let (callback)
      (cl-letf (((symbol-function 'legu--run)
                 (lambda (_root args cb)
                   (should (equal args '("regions" "b.txt" "--json")))
                   (setq callback cb))))
        (legu--file-regions-query)
        (funcall callback 'ok legu-test--rename-answer ""))
      (let ((state (legu--compute)))
        (should (equal (plist-get state :reviewed) '((1 . 10))))
        (should (equal (plist-get state :stale) '((14 . 16))))
        (should (equal (plist-get state :tickets) '(4))))
      ;; The CLI vouched for the whole file, so nothing is left unverified.
      (should-not legu--unaccounted))))

(ert-deftest legu-test-per-file-answer-is-dropped-when-the-buffer-changed ()
  (legu-test--with-file 20
    (let (callback)
      (cl-letf (((symbol-function 'legu--run)
                 (lambda (_root _args cb) (setq callback cb))))
        (legu--file-regions-query)
        (goto-char (point-max))
        (insert "one more line\n")
        (funcall callback 'ok legu-test--rename-answer ""))
      (should-not legu--file-regions))))

(ert-deftest legu-test-per-file-answer-is-dropped-when-a-newer-one-overtakes-it ()
  (legu-test--with-file 20
    (let (callbacks)
      (cl-letf (((symbol-function 'legu--run)
                 (lambda (_root _args cb) (push cb callbacks))))
        (legu--file-regions-query)
        (legu--file-regions-query)
        ;; The older request lands last and says nothing.
        (funcall (cadr callbacks) 'ok legu-test--rename-answer "")
        (should-not legu--file-regions)
        (funcall (car callbacks) 'ok legu-test--rename-answer "")
        (should (equal (plist-get legu--file-regions :reviewed) '((1 . 10))))))))

(ert-deftest legu-test-per-file-answer-is-dropped-when-a-trusted-snapshot-overtakes-it ()
  (legu-test--with-file 20
    (let (callback)
      (cl-letf (((symbol-function 'legu--run)
                 (lambda (_root _args cb) (setq callback cb))))
        (legu--file-regions-query)
        (puthash root (list :state 'fresh
                            :started (time-add (current-time) 60)
                            :rows (make-hash-table :test #'equal))
                 legu--snapshots)
        (funcall callback 'ok legu-test--rename-answer ""))
      (should-not legu--file-regions))))

(ert-deftest legu-test-a-trusted-snapshot-outranks-the-per-file-answer ()
  (legu-test--with-file 20
    (let (callback)
      (cl-letf (((symbol-function 'legu--run)
                 (lambda (_root _args cb) (setq callback cb))))
        (legu--file-regions-query)
        (funcall callback 'ok legu-test--rename-answer ""))
      (should (equal (plist-get (legu--compute) :stale) '((14 . 16))))
      ;; The snapshot lands, and it no longer knows of any stale region here
      ;; -- someone forgot it.  Its verdict is the later one, so the per-file
      ;; answer must not put the stale range back.
      (let ((rows (make-hash-table :test #'equal)))
        (puthash "b.txt" (list :total 20 :reviewed 10 :stale 0 :unreviewed 10
                               :ranges '((1 . 10)))
                 rows)
        (puthash root (list :state 'fresh
                            :started (time-add (current-time) 60)
                            :rows rows
                            :eligible (let ((h (make-hash-table :test #'equal)))
                                        (puthash "b.txt" t h) h)
                            :stale (make-hash-table :test #'equal)
                            :tickets (make-hash-table :test #'equal))
                 legu--snapshots))
      (let ((state (legu--compute)))
        (should (equal (plist-get state :reviewed) '((1 . 10))))
        (should-not (plist-get state :stale))
        (should-not (plist-get state :tickets))))))

(ert-deftest legu-test-a-snapshot-that-cannot-vouch-here-does-not-discard-the-answer ()
  ;; The two tests have to agree.  Discarding the answer on mtime alone,
  ;; while `legu--compute' paints from the stronger one, leaves a buffer
  ;; showing nothing at all until the next save.
  (legu-test--with-file 20
    (let (callback)
      (cl-letf (((symbol-function 'legu--run)
                 (lambda (_root _args cb) (setq callback cb))))
        (legu--file-regions-query)
        ;; A snapshot newer than the request, so it outranks on timing, but
        ;; older than a content change this buffer watched happen -- under a
        ;; backdated mtime, so its own mtime check is fooled and the content
        ;; memo is not.  It may not pronounce here, so it may not silence the
        ;; answer either.
        (set-file-times file (time-subtract (current-time) 86400))
        (setq legu--content-seen (cons "aaa" (time-add (current-time) 60)))
        (puthash root (list :state 'fresh
                            :started (time-add (current-time) 30)
                            :rows (make-hash-table :test #'equal))
                 legu--snapshots)
        (funcall callback 'ok legu-test--rename-answer ""))
      (should (equal (plist-get legu--file-regions :reviewed) '((1 . 10)))))))

(ert-deftest legu-test-per-file-answer-lapses-when-the-file-changes ()
  (legu-test--with-file 20
    (let (callback)
      (cl-letf (((symbol-function 'legu--run)
                 (lambda (_root _args cb) (setq callback cb))))
        (legu--file-regions-query)
        (funcall callback 'ok legu-test--rename-answer ""))
      (should legu--file-regions)
      (with-temp-file file (insert (legu-test--lines 21) "\n"))
      (should-not (plist-get (legu--compute) :reviewed))
      (should-not legu--file-regions))))

(ert-deftest legu-test-incomplete-per-file-answer-keeps-the-unverified-indicator ()
  (legu-test--with-file 20
    (let (callback)
      (cl-letf (((symbol-function 'legu--run)
                 (lambda (_root _args cb) (setq callback cb))))
        (legu--file-regions-query)
        (funcall callback 'ok
                 (string-replace "\"complete\":true" "\"complete\":false"
                                 legu-test--rename-answer)
                 ""))
      ;; What was resolved is painted; the rest is still an open question.
      (should (equal (plist-get (legu--compute) :reviewed) '((1 . 10))))
      (should legu--unaccounted))))

(ert-deftest legu-test-per-file-query-is-not-run-for-a-confirming-sidecar ()
  (legu-test--with-file 20
    (let ((sidecar (expand-file-name ".review/b.txt.jsonl" root)))
      (make-directory (file-name-directory sidecar) t)
      (with-temp-file sidecar
        (insert (format "{\"schema\":3}\n{\"start\":1,\"end\":10,\"reviewer\":\"r\",\"file-hash\":\"%s\"}\n"
                        (legu--file-hash file))))
      (legu--compute)
      (should-not legu--file-regions-wanted)
      ;; Break one hash and the file is no longer accounted for locally.
      (with-temp-file sidecar
        (insert "{\"schema\":3}\n{\"start\":1,\"end\":10,\"reviewer\":\"r\",\"file-hash\":\"deadbeef\"}\n"))
      (legu--compute)
      (should legu--file-regions-wanted))))

(ert-deftest legu-test-integration-rename-paints-before-any-snapshot ()
  "The blind spot this package used to document, now closed."
  (legu-test--with-repo (list (cons "a.txt" (concat (legu-test--lines 20) "\n")))
    (legu-test--legu "mark" "a.txt:1-10")
    (legu-test--git "mv" "a.txt" "b.txt")
    (legu-test--git "commit" "-qam" "rename")
    ;; The sidecar is still keyed by the old path, so tier 0 knows nothing.
    (should-not (plist-get (legu--tier0 root "b.txt" (expand-file-name "b.txt" root))
                           :reviewed))
    (let* ((legu-snapshot-initial-delay 300)
           (legu--seen-roots legu--seen-roots)
           (buffer (find-file-noselect (expand-file-name "b.txt" root))))
      (unwind-protect
          (with-current-buffer buffer
            (legu-mode 1)
            (should (legu-test--wait
                     (lambda () (plist-get legu--painted :reviewed))))
            (should (equal (plist-get legu--painted :reviewed) '((1 . 10))))
            ;; And no repository snapshot was needed to get there.
            (should-not (legu-snapshot root)))
        (kill-buffer buffer)))))

(ert-deftest legu-test-integration-a-copy-inherits-nothing-through-the-painting-path ()
  (legu-test--with-repo (list (cons "a.txt" (concat (legu-test--lines 20) "\n")))
    (legu-test--legu "mark" "a.txt:1-10")
    (copy-file (expand-file-name "a.txt" root) (expand-file-name "b.txt" root))
    (legu-test--git "add" "-A")
    (legu-test--git "commit" "-qm" "copy")
    (let* ((legu-snapshot-initial-delay 300)
           (legu--seen-roots legu--seen-roots)
           (buffer (find-file-noselect (expand-file-name "b.txt" root))))
      (unwind-protect
          (with-current-buffer buffer
            (legu-mode 1)
            (should (legu-test--wait (lambda () legu--file-regions)))
            (should-not (plist-get legu--painted :reviewed))
            (should-not (plist-get legu--painted :stale)))
        (kill-buffer buffer)))))

(ert-deftest legu-test-integration-a-confirming-sidecar-runs-no-subprocess ()
  (legu-test--with-repo (list (cons "a.txt" (concat (legu-test--lines 20) "\n")))
    (legu-test--legu "mark" "a.txt")
    (let* ((legu-snapshot-initial-delay 300)
           (legu--seen-roots legu--seen-roots)
           (ran nil)
           (buffer nil))
      (cl-letf (((symbol-function 'legu--run)
                 (lambda (_root args _cb) (push args ran))))
        (setq buffer (find-file-noselect (expand-file-name "a.txt" root)))
        (unwind-protect
            (with-current-buffer buffer
              (legu-mode 1)
              (should (equal (plist-get legu--painted :reviewed) '((1 . 20))))
              (should-not ran))
          (kill-buffer buffer))))))


;;;; Regressions
;;
;; Each of these is a defect that adversarial review found in this package
;; and that is now fixed.  The comment says what it was.

(ert-deftest legu-test-buffer-lines-counts-the-way-the-cli-does ()
  ;; A newline-terminated file has no extra empty last line, and marking one
  ;; was rejected by the CLI as out of range.
  (with-temp-buffer (insert "a\nb\nc\n") (should (= 3 (legu--buffer-lines))))
  (with-temp-buffer (insert "a\nb\nc")  (should (= 3 (legu--buffer-lines))))
  (with-temp-buffer                      (should (= 0 (legu--buffer-lines))))
  (with-temp-buffer (insert "\n")        (should (= 1 (legu--buffer-lines)))))

(ert-deftest legu-test-marking-at-end-of-buffer-stays-in-range ()
  (legu-test--with-buffer 40
    (setq-local legu--frontier (copy-marker (legu--line-position 1) t))
    (goto-char (point-max))
    (should (equal (legu--target-region nil) '(1 . 40)))))

(ert-deftest legu-test-a-fully-read-file-has-no-phantom-gap ()
  (legu-test--with-buffer 40
    (setq-local legu--painted (list :reviewed '((1 . 40)) :stale nil :total 40))
    (should-not (legu--gaps))))

(ert-deftest legu-test-an-explicit-range-is-honoured-and-validated ()
  ;; The queue and the diff buffer used to fake a selection, which silently
  ;; became "frontier to point" -- an entirely different, much larger region.
  (legu-test--with-buffer 40
    (should (equal (legu--target-region '(10 . 20)) '(10 . 20)))
    (should (equal (legu--target-region '(7 . 7)) '(7 . 7)))
    (should-error (legu--target-region '(35 . 60)) :type 'user-error)
    (should-error (legu--target-region '(0 . 3)) :type 'user-error)
    ;; and the prefix arguments still mean what they meant
    (should-not (legu--target-region '(4)))))

(ert-deftest legu-test-narrowing-does-not-renumber-the-file ()
  ;; Line numbers go to the CLI, which counts lines in the file on disk.
  (legu-test--with-buffer 40
    (narrow-to-region (legu--line-position 21) (legu--line-position 31))
    (goto-char (point-max))
    (should (= 31 (legu--line-number)))
    (should (= 40 (legu--buffer-lines)))
    (setq-local legu--frontier (copy-marker (legu--line-position 21) t))
    (goto-char (legu--line-position 25))
    (should (equal (legu--target-region nil) '(21 . 25)))))

(ert-deftest legu-test-a-sidecar-that-is-a-directory-is-not-an-error ()
  (let* ((dir (make-temp-file "legu-test" t))
         (side (expand-file-name ".review/a.txt.jsonl" dir)))
    (unwind-protect
        (progn
          (make-directory side t)
          (let ((r (legu-sidecar-records dir "a.txt")))
            (should (plist-get r :ok))
            (should-not (plist-get r :regions))))
      (delete-directory dir t))))

(ert-deftest legu-test-backdated-mtime-does-not-buy-trust ()
  ;; A snapshot may only vouch for content it could have seen.  An mtime is
  ;; not proof of that: archives and rsync hand out old ones.
  (let ((file (make-temp-file "legu-test")))
    (unwind-protect
        (with-temp-buffer
          (set-file-times file (time-subtract (current-time) 86400))
          ;; First sight: the mtime is all there is, and it is older, so the
          ;; snapshot may speak.  This is the ordinary case of opening a file
          ;; the last snapshot already covered.
          (should (legu--trusted-here (list :started (current-time)) file
                                      (list :unresolved t :hash "aaa")))
          ;; The content now changes under this buffer's eyes, and the file
          ;; keeps its backdated mtime.  The old snapshot may no longer vouch.
          (set-file-times file (time-subtract (current-time) 86400))
          (should-not (legu--trusted-here (list :started (current-time)) file
                                          (list :unresolved t :hash "bbb")))
          ;; A newer snapshot, taken after the change, may.
          (should (legu--trusted-here
                   (list :started (time-add (current-time) 60)) file
                   (list :unresolved t :hash "bbb"))))
      (delete-file file))))

(ert-deftest legu-test-a-failed-launch-does-not-wedge-the-queue ()
  ;; A signal from the launch used to leave the root marked busy forever,
  ;; which silently swallowed every later write and every later snapshot.
  (let ((legu--write-queues (make-hash-table :test #'equal))
        (legu--write-active (make-hash-table :test #'equal))
        (legu-executable "/nonexistent/legu")
        (seen nil))
    (cl-letf (((symbol-function 'legu-refresh-snapshot) #'ignore))
      (legu--enqueue-write "/r/" '("mark" "a") (lambda (s _o e) (push (cons s e) seen)))
      (legu--enqueue-write "/r/" '("mark" "b") (lambda (s _o e) (push (cons s e) seen))))
    (should (= 2 (length seen)))
    (should (seq-every-p (lambda (x) (eq 'failed (car x))) seen))
    (should-not (gethash "/r/" legu--write-active))
    (should-not (gethash "/r/" legu--write-queues))))

(ert-deftest legu-test-queue-region-sweep-collects-every-distinct-row ()
  (require 'legu-list)
  (with-temp-buffer
    (let ((legu-list--record-cache (make-hash-table :test #'equal)))
      (setq-local legu-list--root "/r/")
      (dolist (spec '(("a.txt" 1 10) ("a.txt" 40 50) ("b.txt" 1 5) ("a.txt" 80 90)))
        (legu-list--row (nth 0 spec) (nth 1 spec) (nth 2 spec) 'stale "x")))
    (goto-char (point-min))
    (push-mark (point) t t)
    (goto-char (point-max))
    (activate-mark)
    (should (= 4 (length (legu-list--rows-in-region))))
    ;; and backwards, which used to drop rows
    (goto-char (point-max))
    (push-mark (point) t t)
    (goto-char (point-min))
    (should (= 4 (length (legu-list--rows-in-region))))
    (deactivate-mark)))

(ert-deftest legu-test-queue-g-refreshes ()
  (require 'legu-list)
  (should (eq 'revert-buffer (keymap-lookup legu-list-mode-map "g"))))

(ert-deftest legu-test-integration-root-matches-the-cli-for-untracked-files ()
  ;; vc-root-dir answers nil for a file git does not track, which sent every
  ;; path to the wrong repository.
  (legu-test--with-repo (list (cons "a.txt" "one\n"))
    (with-temp-file (expand-file-name "fresh.txt" root) (insert "hello\n"))
    (should (equal (file-truename (legu-root (expand-file-name "fresh.txt" root)))
                   (file-truename root)))))

(ert-deftest legu-test-integration-remark-of-a-stale-region-clears-it ()
  ;; The queue and diff buffer's re-mark used to mark the wrong range -- often
  ;; the whole file, sometimes one line short -- so the row never cleared.
  (legu-test--with-repo (list (cons "a.txt" (concat (legu-test--lines 40) "\n")))
    (legu-test--legu "mark" "a.txt:10-20")
    (with-temp-file (expand-file-name "a.txt" root)
      (insert (concat (legu-test--lines 40) "\n"))
      (goto-char (point-min)) (forward-line 14) (insert "changed\n"))
    (should (alist-get 'stale (legu--parse-json
                               (nth 1 (legu-test--legu "stale" "--json")))))
    (let ((buffer (find-file-noselect (expand-file-name "a.txt" root))))
      (unwind-protect
          (with-current-buffer buffer
            (legu-mode 1)
            ;; Re-mark the range `legu stale' prints.
            (let* ((entry (car (alist-get 'stale
                                          (legu--parse-json
                                           (nth 1 (legu-test--legu "stale" "--json"))))))
                   (start (alist-get 'start entry))
                   (end (alist-get 'end entry)))
              (legu-mark (cons start end)))
            (should (legu-test--wait
                     (lambda ()
                       (null (alist-get 'stale
                                        (legu--parse-json
                                         (nth 1 (legu-test--legu "stale" "--json"))))))))
            (let ((records (plist-get (legu-sidecar-records root "a.txt") :regions)))
              (should (= 1 (length records)))))
        (kill-buffer buffer)))))

(defun legu-test--push-a-txt-down-and-change-it (root)
  "Push the 10-20 region of a.txt down a line and change a line inside it.
The record then anchors, stale, at 11-21."
  (with-temp-file (expand-file-name "a.txt" root)
    (insert (concat (legu-test--lines 40) "\n"))
    (goto-char (point-min)) (forward-line 2) (insert "above\n")
    (goto-char (point-min)) (forward-line 15) (insert "changed\n")))

(defun legu-test--stale-regions (_root)
  "What `legu stale --json' reports for the repository at `default-directory'."
  (alist-get 'stale (legu--parse-json (nth 1 (legu-test--legu "stale" "--json")))))

(ert-deftest legu-test-integration-a-containing-mark-supersedes-a-record-anchored-elsewhere ()
  ;; A stale record that now anchors at another range used to survive any
  ;; mark but one on exactly that range, and sat in `legu stale' until
  ;; forgotten.
  (legu-test--with-repo (list (cons "a.txt" (concat (legu-test--lines 40) "\n")))
    (legu-test--legu "mark" "a.txt:10-20")
    (legu-test--push-a-txt-down-and-change-it root)
    (let ((region (car (legu-test--stale-regions root))))
      (should (= 11 (alist-get 'start region)))
      (should (= 21 (alist-get 'end region))))
    (legu-test--legu "mark" "a.txt:10-22")
    (should (null (legu-test--stale-regions root)))
    (should (= 1 (length (plist-get (legu-sidecar-records root "a.txt") :regions))))))

(ert-deftest legu-test-integration-a-partial-re-read-leaves-the-old-record ()
  ;; A partly re-read region is not a read region: the old record stays and
  ;; `legu stale' keeps naming its whole range.
  (legu-test--with-repo (list (cons "a.txt" (concat (legu-test--lines 40) "\n")))
    (legu-test--legu "mark" "a.txt:10-20")
    (legu-test--push-a-txt-down-and-change-it root)
    (legu-test--legu "mark" "a.txt:11-15")
    (let ((region (car (legu-test--stale-regions root))))
      (should (= 11 (alist-get 'start region)))
      (should (= 21 (alist-get 'end region))))
    (should (= 2 (length (plist-get (legu-sidecar-records root "a.txt") :regions))))))

(ert-deftest legu-test-integration-a-whole-file-mark-supersedes-a-record-anchored-elsewhere ()
  ;; `legu mark a.txt' on a text file is a 1-N range, not an opaque region, and
  ;; used to retire nothing.
  (legu-test--with-repo (list (cons "a.txt" (concat (legu-test--lines 40) "\n")))
    (legu-test--legu "mark" "a.txt:10-20")
    (legu-test--push-a-txt-down-and-change-it root)
    (legu-test--legu "mark" "a.txt")
    (should (null (legu-test--stale-regions root)))
    (should (= 1 (length (plist-get (legu-sidecar-records root "a.txt") :regions))))))

(ert-deftest legu-test-integration-a-containing-mark-leaves-ticket-references-alone ()
  ;; Ticket references are independent anchors, not fields of the retired
  ;; record.
  (legu-test--with-repo (list (cons "a.txt" (concat (legu-test--lines 40) "\n")))
    (legu-test--legu "mark" "a.txt:10-20")
    (legu-test--legu "ticket" "a.txt:12-14" "T-1")
    (legu-test--push-a-txt-down-and-change-it root)
    (legu-test--legu "mark" "a.txt:10-22")
    (let ((records (legu-sidecar-records root "a.txt")))
      (should (= 1 (length (plist-get records :regions))))
      (should (= 1 (length (plist-get records :tickets))))
      (should (equal "T-1" (alist-get 'ticket (car (plist-get records :tickets))))))))

(ert-deftest legu-test-integration-a-sidecar-of-another-schema-is-an-error ()
  ;; There are no stores outside this repository, so an older layout is
  ;; refused rather than migrated, by the CLI and by Emacs alike.
  (legu-test--with-repo (list (cons "a.txt" (concat (legu-test--lines 40) "\n")))
    (let ((sidecar (legu-sidecar-file root "a.txt")))
      (make-directory (file-name-directory sidecar) t)
      (with-temp-file sidecar
        (insert "{\"schema\":2}\n")))
    (let ((result (legu-test--legu "status" "--json")))
      (should (= 0 (nth 0 result)))
      (should (string-match-p "cannot read" (nth 2 result)))
      (should (string-match-p
               "schema"
               (alist-get 'reason
                          (car (alist-get 'errors (legu--parse-json (nth 1 result))))))))
    ;; But a mark of that very file still refuses rather than dropping it.
    (should (/= 0 (nth 0 (legu-test--legu "mark" "a.txt:1-5"))))
    (let ((legu--schema-warned nil))
      (should-not (plist-get (legu-sidecar-records root "a.txt") :ok)))))


;;;; Integration: the sidecar layout

(defconst legu-test--hex40 "[0-9a-f]\\{40\\}")
(defconst legu-test--hex64 "[0-9a-f]\\{64\\}")
(defconst legu-test--iso "[0-9]\\{4\\}-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z")

(defun legu-test--record-regexp (region who &optional commit file-hash content-hash)
  "A regexp for one record line as the CLI lays it out.
REGION is \"START,\\\"end\\\":END\" or nil for an opaque record; WHO is the
reviewer or ticket field with its value, e.g. \"\\\"reviewer\\\":\\\"Ada\\\"\".
The timestamp, commit and hashes default to any well-formed value."
  (concat "{" (if region (concat "\"start\":" region) "\"opaque\":true") ","
          who ",\"timestamp\":\"" legu-test--iso "\","
          "\"commit\":\"" (or commit legu-test--hex40) "\","
          "\"file-hash\":\"" (or file-hash legu-test--hex64) "\""
          (if region
              (concat ",\"content-hash\":\"" (or content-hash legu-test--hex64) "\"}\n")
            "}\n")))

(defun legu-test--sidecar-regexp (regions tickets)
  "A regexp for a whole sidecar holding REGIONS and TICKETS record regexps."
  (concat "\\`{\"schema\":3}\n" (apply #'concat regions) (apply #'concat tickets) "\\'"))

(defun legu-test--sidecar-text (root path)
  "The bytes of PATH's sidecar under ROOT, or nil when there is none."
  (let ((file (legu-sidecar-file root path)))
    (when (file-exists-p file)
      (with-temp-buffer
        (set-buffer-multibyte nil)
        (insert-file-contents-literally file)
        (buffer-string)))))

(defun legu-test--write-sidecar (root path text)
  "Overwrite PATH's sidecar under ROOT with TEXT."
  (let ((file (legu-sidecar-file root path)))
    (make-directory (file-name-directory file) t)
    (with-temp-file file (insert text))))

(ert-deftest legu-test-integration-sidecar-layout-is-fixed ()
  "A header line, then one record per line in a fixed key order, every hash
whole, no whitespace anywhere."
  (legu-test--with-repo (list (cons "a.txt" (concat (legu-test--lines 30) "\n")))
    (legu-test--legu "mark" "a.txt:10-20" "--reviewer" "Ada")
    (legu-test--legu "ticket" "a.txt:12-14" "T-1")
    (let ((text (legu-test--sidecar-text root "a.txt")))
      (should (string-match-p
               (legu-test--sidecar-regexp
                (list (legu-test--record-regexp "10,\"end\":20" "\"reviewer\":\"Ada\""))
                (list (legu-test--record-regexp "12,\"end\":14" "\"ticket\":\"T-1\"")))
               text))
      (should-not (string-match-p "path" text))
      (should-not (string-match-p "[ \t]" text)))))

(ert-deftest legu-test-integration-opaque-records-carry-only-the-file-hash ()
  (legu-test--with-repo (list (cons "empty.txt" "")
                              (cons "binary.dat" (concat "a" (unibyte-string 0) "b")))
    (dolist (path '("empty.txt" "binary.dat"))
      (legu-test--legu "mark" path "--reviewer" "Ada")
      (legu-test--legu "ticket" path "T-1")
      (let ((text (legu-test--sidecar-text root path)))
        (should (string-match-p
                 (legu-test--sidecar-regexp
                  (list (legu-test--record-regexp nil "\"reviewer\":\"Ada\""))
                  (list (legu-test--record-regexp nil "\"ticket\":\"T-1\"")))
                 text))
        (should (equal (legu--file-hash (expand-file-name path root))
                       (alist-get 'file-hash
                                  (car (plist-get (legu-sidecar-records root path)
                                                  :regions)))))))))

(defun legu-test--tied-sidecar (root path order)
  "A sidecar for PATH whose records tie on their region, in ORDER, hand-laid.
Keys are out of order, there is whitespace, and ticket references come
before review records: everything a rewrite must put straight."
  (let* ((hash (legu--file-hash (expand-file-name path root)))
         (region (lambda (who)
                   (format "{\"start\": 10, \"end\": 20, \"content-hash\": \"c\", \"file-hash\": \"%s\", \"reviewer\": \"%s\", \"commit\": \"abc\", \"timestamp\": \"2026-08-28T01:00:00Z\"}\n"
                           hash who)))
         (ticket (lambda (id)
                   (format "{\"timestamp\":\"2026-08-28T01:00:00Z\",\"commit\":\"abc\",\"ticket\":\"%s\",\"content-hash\":\"c\",\"file-hash\":\"%s\",\"end\":20,\"start\":10}\n"
                           id hash))))
    (concat "{ \"schema\" : 3 }\n"
            (funcall ticket (nth 2 order))
            (funcall region (nth 0 order))
            (format "{\"start\":25,\"end\":26,\"file-hash\":\"%s\",\"content-hash\":\"c\",\"commit\":\"abc\",\"reviewer\":\"Cy\",\"timestamp\":\"2026-08-28T01:00:00Z\"}\n"
                    hash)
            (funcall ticket (nth 3 order))
            (funcall region (nth 1 order)))))

(ert-deftest legu-test-integration-identical-state-writes-identical-bytes ()
  "Ties on the region are broken by the remaining fields, never by input order."
  (legu-test--with-repo (list (cons "a.txt" (concat (legu-test--lines 30) "\n")))
    (let ((first nil))
      (dolist (order '(("Zed" "Ada" "T-2" "T-1") ("Ada" "Zed" "T-1" "T-2")))
        (legu-test--write-sidecar root "a.txt" (legu-test--tied-sidecar root "a.txt" order))
        (should (= 0 (nth 0 (legu-test--legu "forget" "a.txt:25-26"))))
        (let ((text (legu-test--sidecar-text root "a.txt")))
          (should (string-match-p
                   (legu-test--sidecar-regexp
                    (list (legu-test--record-regexp "10,\"end\":20" "\"reviewer\":\"Ada\"" "abc" nil "c")
                          (legu-test--record-regexp "10,\"end\":20" "\"reviewer\":\"Zed\"" "abc" nil "c"))
                    (list (legu-test--record-regexp "10,\"end\":20" "\"ticket\":\"T-1\"" "abc" nil "c")
                          (legu-test--record-regexp "10,\"end\":20" "\"ticket\":\"T-2\"" "abc" nil "c")))
                   text))
          (if first
              (should (equal first text))
            (setq first text)))))))

(ert-deftest legu-test-integration-an-empty-sidecar-is-removed ()
  (legu-test--with-repo (list (cons "a.txt" (concat (legu-test--lines 30) "\n")))
    (legu-test--legu "mark" "a.txt:10-20")
    (legu-test--legu "ticket" "a.txt:10-20" "T-1")
    (legu-test--legu "forget" "a.txt:10-20")
    (should-not (legu-test--sidecar-text root "a.txt"))
    ;; A sidecar that only ever held ticket references is one too.
    (legu-test--legu "ticket" "a.txt:1-2" "T-2")
    (should (string-match-p "\\`{\"schema\":3}\n{\"start\":1,\"end\":2,\"ticket\":\"T-2\","
                            (legu-test--sidecar-text root "a.txt")))
    (legu-test--legu "forget" "a.txt")
    (should-not (legu-test--sidecar-text root "a.txt"))))

(ert-deftest legu-test-integration-consumers-read-every-kind-of-record ()
  "Text, binary, empty, moved, stale and missing, through persisted sidecars."
  (legu-test--with-repo (list (cons "text.txt" (concat (legu-test--lines 30) "\n"))
                              (cons "binary.dat" (concat "a" (unibyte-string 0) "b"))
                              (cons "empty.txt" "")
                              (cons "moved.txt" (concat (legu-test--lines 30) "\n"))
                              (cons "stale.txt" (concat (legu-test--lines 30) "\n"))
                              (cons "gone.txt" (concat (legu-test--lines 30) "\n")))
    (dolist (target '("text.txt:10-20" "binary.dat" "empty.txt"
                      "moved.txt:10-20" "stale.txt:10-20" "gone.txt:10-20"))
      (should (= 0 (nth 0 (legu-test--legu "mark" target))))
      (should (= 0 (nth 0 (legu-test--legu "ticket" target "T-1")))))
    (with-temp-file (expand-file-name "moved.txt" root)
      (insert "above\nabove\n" (legu-test--lines 30) "\n"))
    (with-temp-file (expand-file-name "stale.txt" root)
      (insert (legu-test--lines 30) "\n")
      (goto-char (point-min)) (forward-line 14) (insert "changed\n"))
    (delete-file (expand-file-name "gone.txt" root))
    (let ((expect (lambda (path state start end moved opaque)
                    (let* ((data (legu-test--regions path))
                           (region (car (alist-get 'regions data)))
                           (ticket (car (alist-get 'tickets data))))
                      (should (= 1 (length (alist-get 'regions data))))
                      (should (= 1 (length (alist-get 'tickets data))))
                      (dolist (r (list region ticket))
                        (should (equal state (alist-get 'state r)))
                        (should (equal start (alist-get 'start r)))
                        (should (equal end (alist-get 'end r)))
                        (should (eq moved (alist-get 'moved r)))
                        (should (eq opaque (alist-get 'opaque r)))
                        (should (equal path (alist-get 'path (alist-get 'original r)))))
                      (should (equal "T-1" (alist-get 'ticket ticket)))))))
      (funcall expect "text.txt" "reviewed" 10 20 nil nil)
      (funcall expect "binary.dat" "reviewed" nil nil nil t)
      (funcall expect "empty.txt" "reviewed" nil nil nil t)
      (funcall expect "moved.txt" "reviewed" 12 22 t nil)
      (funcall expect "stale.txt" "stale" 10 20 nil nil)
      (funcall expect "gone.txt" "missing" nil nil nil nil))
    (let ((stale (legu-test--stale-regions root)))
      (should (equal '("gone.txt" "stale.txt")
                     (sort (mapcar (lambda (r) (alist-get 'path r)) stale) #'string<))))
    (let* ((status (legu--parse-json (nth 1 (legu-test--legu "status" "--json"))))
           (row (lambda (path)
                  (seq-find (lambda (f) (equal path (alist-get 'path f)))
                            (alist-get 'files status)))))
      (should (= 1 (alist-get 'reviewed (funcall row "binary.dat"))))
      (should (= 1 (alist-get 'reviewed (funcall row "empty.txt"))))
      (should (= 11 (alist-get 'reviewed (funcall row "moved.txt"))))
      (should (= 11 (alist-get 'stale (funcall row "stale.txt"))))
      (should (= 6 (length (alist-get 'tickets status)))))
    ;; Every one of them can still be forgotten, the file gone or not.
    (dolist (path '("text.txt" "binary.dat" "empty.txt" "moved.txt" "stale.txt" "gone.txt"))
      (let ((result (legu-test--legu "forget" path)))
        (should (= 0 (nth 0 result)))
        (should (string-match-p "forgot 2 records" (nth 1 result))))
      (should-not (legu-test--sidecar-text root path)))
    (should (null (legu-test--stale-regions root)))))

(ert-deftest legu-test-integration-an-empty-file-is-one-line-to-read ()
  ;; CONTEXT.md: an opaque region counts as one line. It used to count as
  ;; none, so an empty file never entered the numbers or the queue.
  (legu-test--with-repo (list (cons "empty.txt" "")
                              (cons "a.txt" "one\n"))
    (let ((coverage (legu--parse-json (nth 1 (legu-test--legu "coverage" "--json"))))
          (next (legu--parse-json (nth 1 (legu-test--legu "next" "--json")))))
      (should (= 2 (alist-get 'eligible-lines coverage)))
      (should (= 2 (alist-get 'unreviewed coverage)))
      (should (member "empty.txt" (mapcar (lambda (f) (alist-get 'path f))
                                          (alist-get 'next next)))))
    (legu-test--legu "mark" "empty.txt")
    (let ((coverage (legu--parse-json (nth 1 (legu-test--legu "coverage" "--json"))))
          (next (legu--parse-json (nth 1 (legu-test--legu "next" "--json")))))
      (should (= 1 (alist-get 'reviewed coverage)))
      (should (equal '("a.txt") (mapcar (lambda (f) (alist-get 'path f))
                                        (alist-get 'next next)))))))

(defun legu-test--queue (&rest args)
  "The paths `next' suggests, in the order it suggests them."
  (mapcar (lambda (f) (alist-get 'path f))
          (alist-get 'next (legu--parse-json
                            (nth 1 (apply #'legu-test--legu "next" "--json" args))))))

(defun legu-test--commit-edit (paths message)
  "Append a line to each of PATHS and commit them together under MESSAGE.
PATHS are relative to `default-directory'."
  (dolist (path paths)
    (write-region (concat message "\n") nil (expand-file-name path) 'append))
  (legu-test--git "add" "-A")
  (legu-test--git "commit" "-qm" message))

(ert-deftest legu-test-integration-cochange-order-follows-the-commits ()
  ;; a/x.txt is reviewed. c/z.txt landed beside it three times counting the
  ;; commit that created them both, b/y.txt only in that first one, and
  ;; d/w.txt never — so the three scores are 3, 1 and 0, and co-change order
  ;; lifts c/z.txt over b/y.txt while leaving the unscored d/w.txt last.
  (legu-test--with-repo (list (cons "a/x.txt" (concat (legu-test--lines 5) "\n"))
                              (cons "b/y.txt" (concat (legu-test--lines 5) "\n"))
                              (cons "c/z.txt" (concat (legu-test--lines 5) "\n")))
    (legu-test--commit-edit '("a/x.txt" "c/z.txt") "pair one")
    (legu-test--commit-edit '("a/x.txt" "c/z.txt") "pair two")
    ;; A commit with no diff and a merge both list no files, and neither may
    ;; fold one commit's file list into another's.
    (legu-test--git "commit" "-q" "--allow-empty" "-m" "empty marker")
    (legu-test--git "checkout" "-q" "-b" "side")
    (legu-test--commit-edit '("c/z.txt") "side")
    (legu-test--git "checkout" "-q" "-")
    (legu-test--git "merge" "-q" "--no-ff" "-m" "merge" "side")
    ;; d/w.txt is born away from a/x.txt, so nothing ever scores it.
    (make-directory (expand-file-name "d") t)
    (write-region (concat (legu-test--lines 4) "\n") nil
                  (expand-file-name "d/w.txt"))
    (legu-test--commit-edit '("b/y.txt") "solo")
    ;; With nothing reviewed, there is nothing to co-change with.
    (should (equal (legu-test--queue) (legu-test--queue "--order" "cochange")))
    (legu-test--legu "mark" "a/x.txt")
    (should (equal '("b/y.txt" "c/z.txt" "d/w.txt") (legu-test--queue)))
    (should (equal '("b/y.txt" "c/z.txt" "d/w.txt")
                   (legu-test--queue "--order" "dir")))
    (should (equal '("c/z.txt" "b/y.txt" "d/w.txt")
                   (legu-test--queue "--order" "cochange")))
    ;; Same `next' array, same per-file shape, only the order differs.
    (let ((entry (car (alist-get 'next (legu--parse-json
                                        (nth 1 (legu-test--legu
                                                "next" "--json"
                                                "--order" "cochange")))))))
      (should (equal "c/z.txt" (alist-get 'path entry)))
      (should (= 8 (alist-get 'unreviewed entry)))
      (should (= 0 (alist-get 'stale entry)))
      (should (equal "1-8" (alist-get 'ranges entry))))
    ;; An unknown ordering is an error, like every unknown option.
    (should-not (zerop (car (legu-test--legu "next" "--order" "bogus"))))))

(ert-deftest legu-test-integration-cochange-order-needs-git ()
  (unless (legu-test--binary-p) (ert-skip "the legu CLI is not installed"))
  (let* ((root (file-name-as-directory (make-temp-file "legu-nogit" t)))
         (default-directory root))
    (unwind-protect
        (progn
          (make-directory (expand-file-name ".review" root))
          (write-region "one\n" nil (expand-file-name "a.txt" root))
          ;; Without git there is no history to read, but there is still a
          ;; working tree to queue.
          (should (equal '("a.txt") (legu-test--queue)))
          (let ((run (legu-test--legu "next" "--order" "cochange")))
            (should-not (zerop (car run)))
            (should (string-match-p "git" (nth 2 run)))))
      (delete-directory root t))))

(ert-deftest legu-test-integration-emacs-and-the-cli-agree-on-review-evidence ()
  (legu-test--with-repo (list (cons "a.txt" (concat (legu-test--lines 30) "\n"))
                              (cons "empty.txt" ""))
    (legu-test--legu "mark" "a.txt:10-20" "--reviewer" "Ada")
    (legu-test--legu "ticket" "a.txt:12-14" "T-1")
    (legu-test--legu "mark" "empty.txt")
    (let ((tier0 (legu--tier0 root "a.txt" (expand-file-name "a.txt" root)))
          (cli (legu-test--regions "a.txt"))
          (record (legu-region-record-at root "a.txt" 15)))
      (should (equal '((10 . 20)) (plist-get tier0 :reviewed)))
      (should (equal '(12) (plist-get tier0 :tickets)))
      (should-not (plist-get tier0 :unresolved))
      (should (equal "reviewed" (alist-get 'state (car (alist-get 'regions cli)))))
      (should (= 10 (alist-get 'start (car (alist-get 'regions cli)))))
      (should (equal "Ada" (alist-get 'reviewer record)))
      (should (equal (alist-get 'commit record)
                     (alist-get 'commit (alist-get 'original
                                                   (car (alist-get 'regions cli))))))
      (should (equal '("T-1") (legu-tickets-at root "a.txt" 13))))
    ;; An opaque record has no range Emacs could paint; it asks the CLI.
    (let ((tier0 (legu--tier0 root "empty.txt" (expand-file-name "empty.txt" root))))
      (should-not (plist-get tier0 :reviewed))
      (should (plist-get tier0 :unresolved))
      (should (equal "reviewed"
                     (alist-get 'state (car (alist-get 'regions
                                                       (legu-test--regions "empty.txt")))))))
    ;; After an edit inside the region Emacs says nothing; only the CLI says stale.
    (with-temp-file (expand-file-name "a.txt" root)
      (insert (legu-test--lines 30) "\n")
      (goto-char (point-min)) (forward-line 14) (insert "changed\n"))
    (let ((tier0 (legu--tier0 root "a.txt" (expand-file-name "a.txt" root))))
      (should-not (plist-get tier0 :reviewed))
      (should (plist-get tier0 :unresolved))
      (should (equal "stale" (alist-get 'state (car (alist-get 'regions
                                                               (legu-test--regions "a.txt")))))))))

(defun legu-test--numstat (path)
  "Lines added and deleted in PATH's sidecar since HEAD, as (ADDED . DELETED)."
  (with-temp-buffer
    (call-process "git" nil t nil "diff" "--numstat" "--" (concat ".review/" path ".jsonl"))
    (goto-char (point-min))
    (if (looking-at "\\([0-9]+\\)\t\\([0-9]+\\)")
        (cons (string-to-number (match-string 1)) (string-to-number (match-string 2)))
      '(0 . 0))))

(ert-deftest legu-test-integration-a-record-comes-and-goes-without-touching-its-neighbours ()
  (legu-test--with-repo (list (cons "a.txt" (concat (legu-test--lines 40) "\n")))
    (legu-test--legu "mark" "a.txt:1-5")
    (legu-test--legu "mark" "a.txt:10-15")
    (legu-test--legu "mark" "a.txt:20-25")
    (legu-test--git "add" ".review")
    (legu-test--git "commit" "-qm" "reviews")
    ;; A record is one line (ADR-0015), so each of these is one changed line.
    (legu-test--legu "forget" "a.txt:10-15")
    (should (equal '(0 . 1) (legu-test--numstat "a.txt")))
    (legu-test--git "checkout" "-q" "--" ".review")
    (legu-test--legu "mark" "a.txt:30-35")
    (should (equal '(1 . 0) (legu-test--numstat "a.txt")))
    (legu-test--git "checkout" "-q" "--" ".review")
    (legu-test--legu "ticket" "a.txt:12-13" "T-1")
    (should (equal '(1 . 0) (legu-test--numstat "a.txt")))
    (legu-test--git "checkout" "-q" "--" ".review")
    ;; A re-read rewrites who and when, and the commit it was read at: HEAD
    ;; moved when the reviews were committed.
    (legu-test--legu "mark" "a.txt:10-15" "--reviewer" "Bea")
    (should (equal '(1 . 1) (legu-test--numstat "a.txt")))))

(defun legu-test--merge (left right)
  "Apply LEFT and RIGHT on two branches from HEAD and merge them.
Each is a thunk run in the repository.  Returns git's exit status."
  (legu-test--git "branch" "-q" "base")
  (legu-test--git "checkout" "-qb" "left")
  (funcall left)
  (legu-test--git "add" "-A")
  (legu-test--git "commit" "-qm" "left")
  (legu-test--git "checkout" "-q" "base")
  (legu-test--git "checkout" "-qb" "right")
  (funcall right)
  (legu-test--git "add" "-A")
  (legu-test--git "commit" "-qm" "right")
  (legu-test--git "checkout" "-q" "left")
  (legu-test--git "merge" "-q" "--no-edit" "right"))

(defun legu-test--committed-reviews ()
  "Mark three regions of a.txt and commit the sidecar."
  (legu-test--legu "mark" "a.txt:1-5")
  (legu-test--legu "mark" "a.txt:10-15")
  (legu-test--legu "mark" "a.txt:20-25")
  (legu-test--git "add" ".review")
  (legu-test--git "commit" "-qm" "reviews"))

(ert-deftest legu-test-integration-separate-edits-to-one-sidecar-merge ()
  (legu-test--with-repo (list (cons "a.txt" (concat (legu-test--lines 40) "\n")))
    (legu-test--committed-reviews)
    (should (= 0 (legu-test--merge
                  (lambda () (legu-test--legu "forget" "a.txt:10-15"))
                  (lambda () (legu-test--legu "mark" "a.txt:30-35" "--reviewer" "Bea")))))
    (let ((records (legu-sidecar-records root "a.txt")))
      (should (plist-get records :ok))
      (should (equal '((1 . 5) (20 . 25) (30 . 35))
                     (mapcar (lambda (r) (cons (alist-get 'start r) (alist-get 'end r)))
                             (plist-get records :regions)))))
    (should-not (assq 'errors (legu--parse-json (nth 1 (legu-test--legu "status" "--json")))))))

(ert-deftest legu-test-integration-adjacent-edits-to-one-sidecar-conflict ()
  "Two re-reads of neighbouring records are two changed lines with no
unchanged line between them, which git cannot tell from two edits to one
place.  Under the multi-line layout of ADR-0014 the hashes of the first
record stood between the two edits and they merged; one record per line
(ADR-0015) trades that for a one-line diff per mark.  Pinned so the trade
is visible, not so it is wanted."
  (legu-test--with-repo (list (cons "a.txt" (concat (legu-test--lines 40) "\n")))
    (legu-test--committed-reviews)
    (should (/= 0 (legu-test--merge
                   (lambda () (legu-test--legu "mark" "a.txt:1-5" "--reviewer" "Ada"))
                   (lambda () (legu-test--legu "mark" "a.txt:10-15" "--reviewer" "Bea")))))
    (let ((text (legu-test--sidecar-text root "a.txt")))
      (should (string-match-p "^<<<<<<< " text))
      (should (string-match-p "\"Ada\"" text))
      (should (string-match-p "\"Bea\"" text)))
    ;; The conflict markers make the sidecar unreadable to this package too.
    ;; `legu-test-integration-separate-edits-to-one-sidecar-merge' is the
    ;; case that still merges: records one line apart.
    (should-not (plist-get (legu-sidecar-records root "a.txt") :ok))))

(ert-deftest legu-test-integration-competing-edits-to-one-record-conflict ()
  (legu-test--with-repo (list (cons "a.txt" (concat (legu-test--lines 40) "\n")))
    (legu-test--committed-reviews)
    (should (/= 0 (legu-test--merge
                   (lambda () (legu-test--legu "mark" "a.txt:10-15" "--reviewer" "Ada"))
                   (lambda () (legu-test--legu "mark" "a.txt:10-15" "--reviewer" "Bea")))))
    (let ((text (legu-test--sidecar-text root "a.txt")))
      (should (string-match-p "^<<<<<<< " text))
      (should (string-match-p "\"Ada\"" text))
      (should (string-match-p "\"Bea\"" text)))
    ;; The conflict is explicit to legu too: named, and never written over.
    (let ((result (legu-test--legu "status" "--json")))
      (should (= 0 (nth 0 result)))
      (should (equal ".review/a.txt.jsonl"
                     (alist-get 'file (car (alist-get 'errors
                                                      (legu--parse-json (nth 1 result))))))))
    (should (/= 0 (nth 0 (legu-test--legu "mark" "a.txt:20-25"))))))

(ert-deftest legu-test-integration-an-opaque-record-outlives-a-range-mark ()
  ;; A record for a once-empty file is retired by a mark of the whole file it
  ;; became, never by a mark of part of it.
  (legu-test--with-repo (list (cons "e.txt" ""))
    (legu-test--legu "mark" "e.txt")
    (with-temp-file (expand-file-name "e.txt" root)
      (insert (concat (legu-test--lines 40) "\n")))
    (legu-test--legu "mark" "e.txt:10-20")
    (should (= 1 (length (legu-test--stale-regions root))))
    (should (= 2 (length (plist-get (legu-sidecar-records root "e.txt") :regions))))
    (legu-test--legu "mark" "e.txt:1-40")
    (should (null (legu-test--stale-regions root)))
    (should (= 1 (length (plist-get (legu-sidecar-records root "e.txt") :regions))))))

(ert-deftest legu-test-integration-a-mark-after-a-rename-leaves-no-ghost ()
  ;; The record moved with the file, so the mark that re-reads it has to reach
  ;; into the sidecar of the path it was stored under.
  (legu-test--with-repo (list (cons "a.txt" (concat (legu-test--lines 40) "\n")))
    (legu-test--legu "mark" "a.txt:10-20")
    (legu-test--git "mv" "a.txt" "b.txt")
    (legu-test--legu "mark" "b.txt")
    (should (null (legu-test--stale-regions root)))
    (should (= 1 (length (plist-get (legu-sidecar-records root "b.txt") :regions))))
    (should (null (plist-get (legu-sidecar-records root "a.txt") :regions)))))

(ert-deftest legu-test-integration-a-mark-after-a-rename-onto-a-recreated-path-leaves-no-ghost ()
  ;; The old path is back, holding something else, so the file the record was
  ;; stored under is neither missing nor tracked -- and git still calls it the
  ;; rename source.
  (legu-test--with-repo (list (cons "a.txt" (concat (legu-test--lines 40) "\n")))
    (legu-test--legu "mark" "a.txt:10-20")
    (legu-test--git "mv" "a.txt" "b.txt")
    (with-temp-file (expand-file-name "a.txt" root) (insert "something else\n"))
    (legu-test--legu "mark" "b.txt")
    (should (null (legu-test--stale-regions root)))
    (should (= 1 (length (plist-get (legu-sidecar-records root "b.txt") :regions))))
    (should (null (plist-get (legu-sidecar-records root "a.txt") :regions)))))

(ert-deftest legu-test-integration-typing-during-a-mark-keeps-the-alarm-up ()
  ;; The write callback used to clear the unverified flag unconditionally,
  ;; retracting the alarm a later edit had raised -- and then painting
  ;; never-read code as read, in place.
  (legu-test--with-repo (list (cons "a.txt" (concat (legu-test--lines 40) "\n")))
    (let ((buffer (find-file-noselect (expand-file-name "a.txt" root))))
      (unwind-protect
          (with-current-buffer buffer
            (legu-mode 1)
            (legu-mark '(4))
            (goto-char (point-min))
            (insert "CODE NOBODY HAS READ\n")
            (should legu--unverified)
            (should (legu-test--wait
                     (lambda () (plist-get (legu-sidecar-records root "a.txt") :regions))))
            (legu-test--wait (lambda () (not (gethash root legu--write-active))))
            (should (buffer-modified-p))
            (should legu--unverified)
            (legu--repaint)
            ;; Nothing may claim to be read in place: the file on screen is
            ;; not the file legu read.
            (should-not (seq-some (lambda (o)
                                    (memq (overlay-get o 'legu-state) '(reviewed stale)))
                                  legu--overlays)))
        (with-current-buffer buffer (set-buffer-modified-p nil))
        (kill-buffer buffer)))))

(ert-deftest legu-test-integration-whole-file-mark-does-not-overrun-the-file ()
  (legu-test--with-repo (list (cons "a.txt" (concat (legu-test--lines 12) "\n")))
    (let ((buffer (find-file-noselect (expand-file-name "a.txt" root))))
      (unwind-protect
          (with-current-buffer buffer
            (legu-mode 1)
            (setq legu--frontier (copy-marker (legu--line-position 1) t))
            (goto-char (point-max))
            (legu-mark)
            (should (legu-test--wait
                     (lambda () (plist-get (legu-sidecar-records root "a.txt") :regions))))
            (let ((record (car (plist-get (legu-sidecar-records root "a.txt") :regions))))
              (should (= 1 (alist-get 'start record)))
              (should (= 12 (alist-get 'end record))))
            (should-not legu--failures))
        (kill-buffer buffer)))))


;;;; Regressions, round two
;;
;; Defects the second adversarial round found -- several of them introduced by
;; the first round's own fixes.

(ert-deftest legu-test-narrowed-navigation-and-provenance-use-file-lines ()
  (legu-test--with-buffer 40
    (setq-local legu--painted (list :reviewed '((1 . 5)) :stale '((30 . 32)) :total 40))
    (narrow-to-region (legu--line-position 10) (legu--line-position 20))
    (goto-char (point-min))
    (should (= 10 (legu--line-number)))
    ;; The jump target is outside the accessible region; it must not clamp.
    (legu--goto-range '((30 . 32)) t "stale region")
    (should (= 30 (legu--line-number)))))

(ert-deftest legu-test-narrowed-painting-still-covers-the-whole-file ()
  (legu-test--with-buffer 40
    (narrow-to-region (legu--line-position 10) (legu--line-position 20))
    (legu-overlay-paint :reviewed '((1 . 3) (35 . 37)))
    ;; `overlays-in' only sees the accessible portion, so count what was painted.
    (should (= 6 (length legu--overlays)))
    (should (= 6 (length (save-restriction
                           (widen)
                           (legu-test--legu-overlays)))))))

(ert-deftest legu-test-hiding-and-teardown-void-the-content-memo ()
  ;; A snapshot may only vouch for content the buffer was watching when it
  ;; landed; observation lapsing has to void the memo.
  (with-temp-buffer
    (setq-local buffer-file-name "/tmp/x/a")
    (setq-local legu--root "/tmp/x/")
    (setq-local legu-mode t)
    (setq-local legu--relpath "a")
    (setq-local legu--content-seen (cons "aaa" (current-time)))
    (setq-local legu--hidden t)
    (legu--repaint)
    (should-not legu--content-seen)
    (setq-local legu--content-seen (cons "aaa" (current-time)))
    (legu--teardown)
    (should-not legu--content-seen)
    (setq-local buffer-file-name nil)))

(ert-deftest legu-test-a-signalling-callback-is-not-delivered-twice ()
  (let ((legu--write-queues (make-hash-table :test #'equal))
        (legu--write-active (make-hash-table :test #'equal))
        (calls 0))
    (cl-letf (((symbol-function 'legu--run)
               (lambda (_root _args callback) (funcall callback 'ok "" "")))
              ((symbol-function 'legu-refresh-snapshot) #'ignore))
      (should-error
       (legu--enqueue-write "/r/" '("mark" "a")
                            (lambda (&rest _) (setq calls (1+ calls)) (error "boom")))))
    (should (= 1 calls))))

(ert-deftest legu-test-integration-a-save-that-moves-the-region-is-refused ()
  ;; legu-mark saves before measuring, so the region it names is the region on
  ;; disk.  A formatter that rewrites the buffer wholesale collapses the mark;
  ;; recording "1 to end" instead of two lines would be the worst kind of lie.
  (legu-test--with-repo (list (cons "a.txt" (concat (legu-test--lines 20) "\n")))
    (let ((buffer (find-file-noselect (expand-file-name "a.txt" root))))
      (unwind-protect
          (with-current-buffer buffer
            (legu-mode 1)
            (add-hook 'before-save-hook
                      (lambda () (let ((text (buffer-string)))
                                   (erase-buffer) (insert text)))
                      nil t)
            (goto-char (legu--line-position 6))
            (insert "edited\n")
            (push-mark (legu--line-position 6) t t)
            (goto-char (legu--line-position 8))
            (activate-mark)
            (should-error (legu-mark) :type 'user-error)
            (deactivate-mark)
            (should-not (plist-get (legu-sidecar-records root "a.txt") :regions)))
        (with-current-buffer buffer (set-buffer-modified-p nil))
        (kill-buffer buffer)))))

(ert-deftest legu-test-integration-cr-only-files-are-refused ()
  ;; The CLI splits on newlines only, so such a file is one line to it.
  (legu-test--with-repo (list (cons "mac.txt" "a\rb\rc\rd\re\r"))
    (let ((buffer (find-file-noselect (expand-file-name "mac.txt" root))))
      (unwind-protect
          (with-current-buffer buffer
            (legu-mode 1)
            (should (eq 2 (coding-system-eol-type buffer-file-coding-system)))
            (should-error (legu-mark '(4)) :type 'user-error)
            (should-not (plist-get (legu-sidecar-records root "mac.txt") :regions)))
        (kill-buffer buffer)))))

(ert-deftest legu-test-integration-diff-remark-uses-the-regions-current-lines ()
  ;; The record says where the region was read; the paint says where it is now.
  ;; Re-marking the stored coordinates would record lines nobody has read.
  (legu-test--with-repo (list (cons "a.txt" (concat (legu-test--lines 40) "\n")))
    (legu-test--legu "mark" "a.txt:20-30")
    (with-temp-file (expand-file-name "a.txt" root)
      (insert (concat (legu-test--lines 40) "\n"))
      (goto-char (point-min)) (insert "one\ntwo\nthree\n")
      (goto-char (legu-test--line-pos 27)) (insert "changed\n"))
    (let ((buffer (find-file-noselect (expand-file-name "a.txt" root))))
      (unwind-protect
          (with-current-buffer buffer
            (legu-mode 1)
            (legu-refresh-snapshot root)
            (should (legu-test--wait (lambda () (plist-get (legu-snapshot root) :coverage))))
            (legu--repaint)
            (let ((stale (car (plist-get legu--painted :stale))))
              (should stale)
              ;; the region moved down by the three inserted lines
              (should (= 23 (car stale)))
              (goto-char (legu--line-position (car stale)))
              (legu-diff-stale)
              (with-current-buffer (get-buffer (format "*legu-diff: %s*" "a.txt"))
                ;; the record says 20-30; the region now sits at 23-33
                (should (= 23 (plist-get legu-diff--source :start)))
                (should (= 33 (plist-get legu-diff--source :end)))
                (should (= 20 (alist-get 'start
                                         (legu-region-record-at root "a.txt" 20)))))))
        (kill-buffer buffer)))))

;;;; Evil

;; What evil highlights is not what `region-beginning' and `region-end'
;; report, and legu records lines: every case below marked the wrong lines
;; before `legu--visual-region' existed.  `V' on one line was the worst --
;; mark and point end up equal, `use-region-p' is nil, and the mark fell
;; through to "from the frontier down to point", recording lines above the
;; selection that nobody had read.

(defun legu-test--evil-p ()
  "Whether evil is installed."
  (require 'evil nil t))

(defmacro legu-test--with-evil-buffer (contents &rest body)
  "Run BODY in a live buffer of CONTENTS with evil on, in normal state."
  (declare (indent 1))
  `(let ((buffer (generate-new-buffer " *legu-evil-test*")))
     (unwind-protect
         (progn
           (switch-to-buffer buffer)
           (with-current-buffer buffer
             (insert ,contents)
             (evil-local-mode 1)
             (evil-normal-state)
             (evil-normalize-keymaps)
             ,@body))
       (kill-buffer buffer))))

(ert-deftest legu-test-evil-visual-selection-names-the-lines-evil-highlights ()
  (skip-unless (legu-test--evil-p))
  (require 'legu-evil)
  (dolist (case '(("V" 2 . 2) ("Vj" 2 . 3) ("Vjj" 2 . 4)
                  ("v" 2 . 2) ("vj" 2 . 3) ("vjj" 2 . 4) ("vj$" 2 . 3)
                  ("viw" 2 . 2) ("VG" 2 . 5) ("vG" 2 . 5)))
    (legu-test--with-evil-buffer "line one\nline two\nline three\nline four\nline five\n"
      (goto-char (point-min))
      (forward-line 1)                  ; line 2 of 5
      (execute-kbd-macro (kbd (car case)))
      (should (equal (cons (cadr case) (cddr case)) (legu--target-region nil)))
      ;; and a selection is a selection, so the big-mark confirmation and
      ;; every other caller sees one
      (should (legu--selection-p))
      (evil-exit-visual-state))))

(ert-deftest legu-test-evil-rows-in-region-collects-every-selected-row ()
  (skip-unless (legu-test--evil-p))
  (require 'legu-evil)
  (legu-test--with-evil-buffer ""
    (let ((inhibit-read-only t))
      (legu-list-mode)
      (evil-local-mode 1)
      (evil-normal-state)
      (insert "heading\n")
      (legu-list--row "a.txt" 1 10 'stale "one")
      (legu-list--row "b.txt" 5 15 'stale "two")
      (legu-list--row "c.txt" 1 20 'stale "three"))
    (goto-char (point-min))
    (forward-line 1)                    ; the a.txt row
    (execute-kbd-macro (kbd "Vj"))
    (should (equal '("a.txt" "b.txt")
                   (mapcar (lambda (r) (plist-get r :path))
                           (legu-list--rows-in-region))))
    (evil-exit-visual-state)
    (goto-char (point-min))
    (forward-line 1)
    (execute-kbd-macro (kbd "V"))
    (should (equal '("a.txt")
                   (mapcar (lambda (r) (plist-get r :path))
                           (legu-list--rows-in-region))))
    (evil-exit-visual-state)))

(ert-deftest legu-test-evil-queue-keys-are-legus-and-not-compilations ()
  (skip-unless (legu-test--evil-p))
  (require 'legu-evil)
  (legu-test--with-evil-buffer ""
    (legu-list-mode)
    (evil-local-mode 1)
    (evil-normal-state)
    (evil-normalize-keymaps)
    ;; RET is the one that matters most: `compile-goto-error' reads the
    ;; text of the row, `legu-list-visit' reads its properties.
    (should (eq #'legu-list-visit (key-binding (kbd "RET"))))
    (should (eq #'revert-buffer (key-binding (kbd "gr"))))
    (should (eq #'legu-list-mark (key-binding (kbd "r"))))
    (should (eq #'legu-list-diff (key-binding (kbd "d"))))
    (should (eq #'legu-list-forget (key-binding (kbd "x"))))
    (should (eq #'legu-list-ticket (key-binding (kbd "a"))))
    (should (eq #'legu-dispatch (key-binding (kbd "?"))))
    ;; motions stay motions
    (should (eq #'evil-next-line (key-binding (kbd "j"))))
    (should (eq #'evil-previous-line (key-binding (kbd "k"))))
    ;; and marking is reachable from visual state, where the selection is
    (evil-visual-line)
    (evil-normalize-keymaps)
    (should (eq #'legu-list-mark (key-binding (kbd "r"))))
    (evil-exit-visual-state)))

(ert-deftest legu-test-evil-source-buffer-keeps-its-prefix-and-gains-motions ()
  (skip-unless (legu-test--evil-p))
  (require 'legu-evil)
  (legu-test--with-evil-buffer "one\ntwo\nthree\n"
    (setq-local legu-mode t)
    (evil-normalize-keymaps)
    ;; the prefix works unchanged in normal state
    (should (eq #'legu-mark (key-binding (kbd "C-c r r"))))
    (should (eq #'legu-set-frontier (key-binding (kbd "C-c r SPC"))))
    ;; and the bracket motions are there
    (should (eq #'legu-next-stale (key-binding (kbd "]r"))))
    (should (eq #'legu-previous-stale (key-binding (kbd "[r"))))
    (should (eq #'legu-next-gap (key-binding (kbd "]g"))))
    (should (eq #'legu-previous-gap (key-binding (kbd "[g"))))))

(ert-deftest legu-test-evil-quitting-the-diff-restores-the-windows ()
  (skip-unless (legu-test--evil-p))
  (require 'legu-evil)
  ;; evil-collection binds `q' to `quit-window' in a minor mode map that no
  ;; major mode keymap outranks, which would drop the saved window
  ;; configuration on the floor; a remap catches it whoever bound it.
  (should (eq #'legu-diff-quit
              (lookup-key legu-diff-mode-map [remap quit-window])))
  (legu-test--with-evil-buffer ""
    (legu-diff-mode)
    (evil-local-mode 1)
    (evil-normal-state)
    (evil-normalize-keymaps)
    (should (eq #'legu-diff-quit (key-binding (kbd "q"))))
    (should (eq #'legu-diff-remark (key-binding (kbd "r"))))
    (should (eq #'legu-diff-ediff (key-binding (kbd "="))))))

(ert-deftest legu-test-evil-marking-ends-the-selection ()
  (skip-unless (legu-test--evil-p))
  (require 'legu-evil)
  (should (advice-member-p #'legu-evil--exit-visual-state 'legu-mark))
  (legu-test--with-evil-buffer "one\ntwo\nthree\n"
    (goto-char (point-min))
    (execute-kbd-macro (kbd "Vj"))
    (should (evil-visual-state-p))
    (legu-evil--exit-visual-state)
    (should-not (evil-visual-state-p))))


(defun legu-test--line-pos (line)
  "Position of LINE in the current temp buffer."
  (save-excursion (goto-char (point-min)) (forward-line (1- line)) (point)))


;;;; The dired column

(defun legu-test--cell (cell)
  "CELL as a comparable list: (TOTAL REVIEWED STALE UNCERTAIN)."
  (and cell (list (plist-get cell :total) (plist-get cell :reviewed)
                  (plist-get cell :stale) (and (plist-get cell :uncertain) t))))

(ert-deftest legu-test-dired-directory-cells-are-line-weighted-sums ()
  (let* ((rows (legu-test--rows '(("src/a.el" 100 72 3)
                                  ("src/core/b.el" 50 0 0)
                                  ("README.md" 10 10 0))))
         (uncertain (lambda (path) (equal path "src/core/b.el")))
         (cells (legu-dired--directory-cells rows "" uncertain)))
    ;; Every ancestor gets the file's lines; the root is the empty key.
    (should (equal (legu-test--cell (gethash "" cells)) '(160 82 3 t)))
    (should (equal (legu-test--cell (gethash "src" cells)) '(150 72 3 t)))
    (should (equal (legu-test--cell (gethash "src/core" cells)) '(50 0 0 t)))
    ;; A directory with no eligible file beneath it has no cell at all.
    (should-not (gethash "docs" cells))
    ;; Files are not directories.
    (should-not (gethash "src/a.el" cells))))

(ert-deftest legu-test-dired-directory-cells-inherit-uncertainty-only-from-beneath ()
  (let* ((rows (legu-test--rows '(("src/a.el" 100 72 3)
                                  ("src/core/b.el" 50 0 0))))
         (uncertain (lambda (path) (equal path "src/a.el")))
         (cells (legu-dired--directory-cells rows "" uncertain)))
    (should (equal (legu-test--cell (gethash "src" cells)) '(150 72 3 t)))
    (should (equal (legu-test--cell (gethash "src/core" cells)) '(50 0 0 nil)))))

(ert-deftest legu-test-dired-directory-cells-scoped-to-a-subtree ()
  ;; Only the subtree on screen is summed, and never a partial ancestor.
  (let* ((rows (legu-test--rows '(("src/a.el" 100 72 3)
                                  ("src/core/b.el" 50 0 0)
                                  ("src-x/c.el" 10 10 0)
                                  ("README.md" 10 10 0))))
         (cells (legu-dired--directory-cells rows "src" #'ignore)))
    (should (equal (legu-test--cell (gethash "src" cells)) '(150 72 3 nil)))
    (should (equal (legu-test--cell (gethash "src/core" cells)) '(50 0 0 nil)))
    (should-not (gethash "" cells))
    (should-not (gethash "src-x" cells))))

(defun legu-test--faces (s)
  "The (CHAR . FACE) pairs of S, for characters that carry a face."
  (let (out)
    (dotimes (i (length s))
      (when-let* ((face (get-text-property i 'face s)))
        (push (cons (aref s i) face) out)))
    (nreverse out)))

(ert-deftest legu-test-dired-cell-shows-floor-reviewed-and-ceiling-stale ()
  ;; 729 of 1000 is 72.9%: floor.  21 of 1000 is 2.1%: ceiling.  Both
  ;; rounding errors point at remaining work.
  (should (equal (substring-no-properties
                  (legu-dired--format-cell (list :total 1000 :reviewed 729 :stale 21)))
                 "72% 3%  "))
  ;; A zero stale count is blank, not "0%".
  (should (equal (substring-no-properties
                  (legu-dired--format-cell (list :total 100 :reviewed 100 :stale 0)))
                 "100%    "))
  (should (equal (substring-no-properties
                  (legu-dired--format-cell (list :total 100 :reviewed 0 :stale 0)))
                 "0%      "))
  ;; Every cell is the same width.
  (dolist (cell (list nil
                      (list :total 0 :reviewed 0 :stale 0)
                      (list :total 3 :reviewed 1 :stale 1 :uncertain t)
                      (list :total 100 :reviewed 0 :stale 100 :uncertain t)))
    (should (= (length (legu-dired--format-cell cell)) legu-dired--column-width))))

(ert-deftest legu-test-dired-cell-marks-what-the-snapshot-cannot-vouch-for ()
  (should (equal (substring-no-properties
                  (legu-dired--format-cell
                   (list :total 100 :reviewed 72 :stale 3 :uncertain t)))
                 "72% 3%? ")))

(ert-deftest legu-test-dired-cell-is-a-dash-when-nothing-counts ()
  (should (equal (substring-no-properties (legu-dired--format-cell nil)) "—       "))
  ;; An opaque or empty file has no lines to weigh.
  (should (equal (substring-no-properties
                  (legu-dired--format-cell (list :total 0 :reviewed 0 :stale 0)))
                 "—       ")))

(ert-deftest legu-test-dired-cell-faces ()
  ;; The gutter's own faces, so the column doubles as its legend: reviewed
  ;; is legu-reviewed, stale is legu-stale, ? and — are dimmed.  No
  ;; thresholds; the one extra signal is bold at 100%, a state, not a score.
  (should (equal (legu-test--faces
                  (legu-dired--format-cell (list :total 100 :reviewed 72 :stale 3 :uncertain t)))
                 '((?7 . legu-reviewed) (?2 . legu-reviewed) (?% . legu-reviewed)
                   (?3 . legu-stale) (?% . legu-stale) (?? . legu-unverified))))
  (should (equal (legu-test--faces (legu-dired--format-cell nil))
                 '((?— . legu-ignored))))
  (should (equal (legu-test--faces (legu-dired--format-cell (list :total 100 :reviewed 100 :stale 0)))
                 '((?1 . (bold legu-reviewed)) (?0 . (bold legu-reviewed))
                   (?0 . (bold legu-reviewed)) (?% . (bold legu-reviewed)))))
  ;; 99% is not 100%.
  (should (equal (legu-test--faces (legu-dired--format-cell (list :total 1000 :reviewed 999 :stale 0)))
                 '((?9 . legu-reviewed) (?9 . legu-reviewed) (?% . legu-reviewed)))))

(defmacro legu-test--with-dired-tree (root-var &rest body)
  "Run BODY in a dired buffer over a scratch tree bound to ROOT-VAR.
The tree has a .review store, src/a.el and src/core/b.el, README.md,
docs/x.md (ineligible) and an empty dir.  The snapshot is hand-built
and has rows for everything but docs/x.md."
  (declare (indent 1))
  `(let* ((,root-var (file-name-as-directory
                      (make-temp-file "legu-dired" t)))
          (legu--snapshots (make-hash-table :test #'equal))
          (legu--seen-roots nil)
          (legu--watchers (make-hash-table :test #'equal))
          (legu-watch-store nil)
          (legu--root-cheap-cache (make-hash-table :test #'equal)))
     (unwind-protect
         (progn
           (dolist (d '(".review" "src/core" "docs" "empty"))
             (make-directory (expand-file-name d ,root-var) t))
           (dolist (f '("src/a.el" "src/core/b.el" "README.md" "docs/x.md"))
             (write-region "x\n" nil (expand-file-name f ,root-var)))
           (puthash ,root-var
                    (list :state 'fresh
                          :started (time-add (current-time) 60)
                          :rows (legu-test--rows '(("src/a.el" 100 72 3)
                                                   ("src/core/b.el" 50 0 0)
                                                   ("README.md" 10 10 0))))
                    legu--snapshots)
           (with-current-buffer (dired-noselect ,root-var)
             (unwind-protect (progn ,@body)
               (kill-buffer))))
       (delete-directory ,root-var t))))

(defun legu-test--dired-goto (file)
  "Move to FILE's line; `dired-goto-file' does not know `.' and `..'."
  (if (member file '("." ".."))
      (progn
        (goto-char (point-min))
        (while (not (equal (dired-get-filename 'no-dir t) file))
          (should (zerop (forward-line 1)))
          (should-not (eobp))))
    (should (dired-goto-file (expand-file-name file default-directory))))
  (dired-move-to-filename))

(defun legu-test--dired-column (file)
  "The column text drawn before FILE in this dired buffer, or nil."
  (save-excursion
    (legu-test--dired-goto file)
    (when-let* ((ov (seq-find (lambda (o) (overlay-get o 'legu-dired))
                              (overlays-at (point)))))
      (substring-no-properties (overlay-get ov 'before-string)))))

(ert-deftest legu-test-dired-column-renders-from-the-snapshot ()
  (legu-test--with-dired-tree root
    (legu-dired-mode 1)
    (should (equal (legu-test--dired-column "src") "48% 2%   "))
    (should (equal (legu-test--dired-column "README.md") "100%     "))
    ;; A directory with no eligible file beneath it, and an ineligible file.
    (should (equal (legu-test--dired-column "docs") "—        "))
    (should (equal (legu-test--dired-column "empty") "—        "))
    ;; An inserted subdirectory gets the column too.
    (dired-insert-subdir (expand-file-name "src" root))
    (should (equal (legu-test--dired-column "src/a.el") "72% 3%   "))
    (should (equal (legu-test--dired-column "src/core") "0%       "))
    (dired-goto-subdir (expand-file-name "docs" root))
    ;; The column survives hiding the details.
    (dired-hide-details-mode 1)
    (should (equal (legu-test--dired-column "README.md") "100%     "))
    ;; And leaves nothing behind.
    (legu-dired-mode -1)
    (should-not (legu-test--dired-column "src"))))

(ert-deftest legu-test-dired-column-in-a-subdirectory-sums-only-what-is-listed ()
  (legu-test--with-dired-tree root
    (with-current-buffer (dired-noselect (expand-file-name "src" root))
      (unwind-protect
          (progn
            (legu-dired-mode 1)
            (should (equal (legu-test--dired-column "a.el") "72% 3%   "))
            (should (equal (legu-test--dired-column "core") "0%       "))
            ;; `.' is this directory; `..' lies above what was summed, and
            ;; a dash there would claim the parent has nothing to review.
            (should (equal (legu-test--dired-column ".") "48% 2%   "))
            (should-not (legu-test--dired-column "..")))
        (kill-buffer)))))

(ert-deftest legu-test-dired-column-inherits-the-question-mark ()
  (legu-test--with-dired-tree root
    ;; b.el is newer than the snapshot: its numbers, and those of every
    ;; directory above it, carry a ?.
    (set-file-times (expand-file-name "src/core/b.el" root)
                    (time-add (current-time) 120))
    (legu-dired-mode 1)
    (should (equal (legu-test--dired-column "src") "48% 2%?  "))
    (should (equal (legu-test--dired-column "README.md") "100%     "))
    (dired-insert-subdir (expand-file-name "src" root))
    (should (equal (legu-test--dired-column "src/a.el") "72% 3%   "))
    (should (equal (legu-test--dired-column "src/core") "0%?      "))))

(ert-deftest legu-test-dired-column-is-blank-until-a-snapshot-lands ()
  (legu-test--with-dired-tree root
    (let ((snapshot (gethash root legu--snapshots)))
      (remhash root legu--snapshots)
      (legu-dired-mode 1)
      ;; Blank, and a snapshot has been asked for.
      (should-not (legu-test--dired-column "src"))
      (should (member root legu--seen-roots))
      ;; It lands: the column appears without a revert.
      (puthash root snapshot legu--snapshots)
      (legu-dired-refresh-buffers root)
      (should (equal (legu-test--dired-column "src") "48% 2%   ")))))

(ert-deftest legu-test-dired-column-follows-global-legu-mode ()
  (legu-test--with-dired-tree root
    (let ((global-legu-mode t))
      (let ((legu-dired-column nil))
        (legu--turn-on-maybe)
        (should-not legu-dired-mode))
      (legu--turn-on-maybe)
      (should legu-dired-mode)
      (should (equal (legu-test--dired-column "src") "48% 2%   "))
      ;; Turning the global mode off takes the column with it.
      (let ((global-legu-mode nil))
        (run-hooks 'global-legu-mode-hook))
      (should-not legu-dired-mode))))


(provide 'legu-tests)
;;; legu-tests.el ends here
