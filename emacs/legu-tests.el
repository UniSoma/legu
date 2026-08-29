;;; legu-tests.el --- Tests for legu.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Jonas Rodrigues
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Two tiers.  The first is pure: range arithmetic, the EDN reader, the
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


;;;; The EDN reader

(defconst legu-test--sidecar "\
{:schema 1,
 :path \"src/a.txt\",
 :regions
 [{:start 10,
   :end 20,
   :commit \"c439a98805096d822fb420ffa3a37564ad124f58\",
   :file-hash
   \"be9c2c9ae93d3e3f9279aed5036406b927bac3257ea456970903bb0bcf9c65f9\",
   :content-hash \"d65c7b\",
   :reviewer \"a \\\"quoted\\\" name\",
   :timestamp \"2026-08-28T10:00:28.735025487Z\",
   :notes [\"lgu-01k7\" \"lgu-02\"]}],
 :notes
 [{:start 10, :end 20, :ticket \"lgu-01k7\", :opaque true, :file-hash \"be9c2c\"}]}
")

(ert-deftest legu-test-edn-reads-a-real-sidecar ()
  (let* ((data (legu--read-edn legu-test--sidecar))
         (region (car (alist-get 'regions data)))
         (note (car (alist-get 'notes data))))
    (should (eql 1 (alist-get 'schema data)))
    (should (equal "src/a.txt" (alist-get 'path data)))
    (should (eql 10 (alist-get 'start region)))
    (should (eql 20 (alist-get 'end region)))
    (should (equal "a \"quoted\" name" (alist-get 'reviewer region)))
    (should (equal '("lgu-01k7" "lgu-02") (alist-get 'notes region)))
    (should (eq t (alist-get 'opaque note)))))

(ert-deftest legu-test-edn-never-signals ()
  (dolist (bad (list "<<<<<<< HEAD\n{:schema 1}\n=======\n"
                     "{:schema 1, :path"
                     "#inst \"2026-01-01\""
                     "[1 2 3]"
                     ""
                     "{:a #{1 2}}"))
    (should-not (legu--read-edn bad))))

(ert-deftest legu-test-edn-schema-gate ()
  (let* ((dir (make-temp-file "legu-test" t))
         (side (expand-file-name ".review/a.txt.edn" dir)))
    (unwind-protect
        (progn
          (make-directory (file-name-directory side) t)
          (with-temp-file side (insert "{:schema 2, :path \"a.txt\", :regions []}"))
          (let ((legu--schema-warned nil))
            (should-not (plist-get (legu-sidecar-records dir "a.txt") :ok)))
          (with-temp-file side (insert legu-test--sidecar))
          (should (plist-get (legu-sidecar-records dir "a.txt") :ok))
          (should (= 1 (length (plist-get (legu-sidecar-records dir "a.txt") :regions)))))
      (delete-directory dir t))))

(ert-deftest legu-test-edn-missing-sidecar-is-ok-and-empty ()
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
    (legu-overlay-paint :reviewed '((3 . 5)) :stale '((10 . 11)) :notes '(3))
    (should (> (length (legu-test--legu-overlays)) 0))
    (legu-overlay-clear)
    (should (= 0 (length (legu-test--legu-overlays))))))

(ert-deftest legu-test-note-glyph-wins-the-line ()
  (legu-test--with-buffer 20
    (legu-overlay-paint :reviewed '((3 . 5)) :notes '(3))
    (let ((states (mapcar (lambda (o) (overlay-get o 'legu-state))
                          (legu-test--legu-overlays))))
      (should (memq 'note states))
      ;; Exactly one overlay per line: 3 is the note, 4 and 5 reviewed.
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
      (setq-local legu--tier0-unresolved t)
      (should (equal (substring-no-properties (legu--lighter)) " legu 61%?"))
      (setq-local legu--tier0-unresolved nil)
      (setq-local legu--unverified t)
      (should (equal (substring-no-properties (legu--lighter)) " legu?"))
      (setq-local legu--unverified nil)
      (setq-local legu--scope 'out)
      (should (equal (substring-no-properties (legu--lighter)) " legu —"))
      (setq-local legu--scope 'in)
      (puthash "/tmp/x/" (list :state 'error) legu--snapshots)
      (should (equal (substring-no-properties (legu--lighter)) " legu!")))))


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
      (should (= (plist-get mine :never) (alist-get 'never-read theirs)))
      (should (= (length queue) (length their-queue)))
      (cl-loop for row in queue
               for other in their-queue
               do (should (equal (plist-get row :path) (alist-get 'path other)))
               do (should (= (plist-get row :unreviewed) (alist-get 'unreviewed other)))
               do (should (= (plist-get row :stale) (alist-get 'stale other)))
               do (should (equal (legu-format-ranges (plist-get row :ranges))
                                 (alist-get 'ranges other)))))))

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

(ert-deftest legu-test-integration-broken-store-is-survivable ()
  (legu-test--with-repo (list (cons "a.txt" (concat (legu-test--lines 10) "\n"))
                              (cons "b.txt" (concat (legu-test--lines 10) "\n")))
    (legu-test--legu "mark" "a.txt:1-5")
    (legu-test--legu "mark" "b.txt:1-5")
    (with-temp-file (expand-file-name ".review/b.txt.edn" root)
      (insert "<<<<<<< HEAD\n{:schema 1}\n=======\nnonsense\n>>>>>>> other\n"))
    (let ((result (legu-test--legu "status" "--json")))
      (should (/= 0 (nth 0 result)))
      (should (string-empty-p (string-trim (nth 1 result))))
      (should (string-match legu--broken-store-rx (nth 2 result))))
    ;; The CLI is down, but the other file still paints from its own sidecar.
    (should (equal '((1 . 5))
                   (plist-get (legu--tier0 root "a.txt" (expand-file-name "a.txt" root))
                              :reviewed)))
    (should-not (plist-get (legu-sidecar-records root "b.txt") :ok))
    ;; And the package records the error rather than looking dead.
    (legu-refresh-snapshot root)
    (should (legu-test--wait
             (lambda () (eq 'error (plist-get (legu-snapshot root) :state)))))
    (should (equal 'broken-store
                   (plist-get (plist-get (legu-snapshot root) :error) :kind)))))

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

(ert-deftest legu-test-integration-rename-is-the-documented-tier0-blind-spot ()
  ;; Asserts the limit, so a future fix breaks this test visibly.
  (legu-test--with-repo (list (cons "a.txt" (concat (legu-test--lines 20) "\n")))
    (legu-test--legu "mark" "a.txt:1-10")
    (legu-test--git "mv" "a.txt" "b.txt")
    (legu-test--git "commit" "-qam" "rename")
    (should-not (plist-get (legu--tier0 root "b.txt" (expand-file-name "b.txt" root))
                           :reviewed))
    ;; The CLI still follows it, so the snapshot repairs the picture.
    (legu-refresh-snapshot root)
    (should (legu-test--wait (lambda () (plist-get (legu-snapshot root) :coverage))))
    (let ((row (gethash "b.txt" (plist-get (legu-snapshot root) :rows))))
      (should (equal (plist-get row :ranges) '((1 . 10)))))))

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

(ert-deftest legu-test-integration-cli-surface-is-what-we-speak ()
  "Canary for a CLI upgrade that changes the surface out from under us."
  (unless (legu-test--binary-p) (ert-skip "the legu CLI is not installed"))
  (let ((result (legu-test--legu "--help")))
    (should (= 0 (nth 0 result)))
    (dolist (word '("mark" "note" "forget" "status" "stale" "next" "coverage"
                    "--json" "--reviewer" "--limit"))
      (should (string-match-p (regexp-quote word) (nth 1 result))))))


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

(ert-deftest legu-test-edn-reads-the-escapes-clojure-prints ()
  (let ((data (legu--read-edn "{:schema 1, :reviewer \"a\\fb\\bc\\td\"}")))
    (should (equal (alist-get 'reviewer data) "a\fb\bc\td"))))

(ert-deftest legu-test-a-sidecar-that-is-a-directory-is-not-an-error ()
  (let* ((dir (make-temp-file "legu-test" t))
         (side (expand-file-name ".review/a.txt.edn" dir)))
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
            ;; Re-mark the range `legu stale' prints -- the CLI supersedes a
            ;; record only where it currently sits.
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
    (should (eq #'legu-list-note (key-binding (kbd "a"))))
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
  ;; Reviewed is the default face; stale is legu-stale; ? and — are dimmed.
  (should (equal (legu-test--faces
                  (legu-dired--format-cell (list :total 100 :reviewed 72 :stale 3 :uncertain t)))
                 '((?3 . legu-stale) (?% . legu-stale) (?? . legu-unverified))))
  (should (equal (legu-test--faces (legu-dired--format-cell nil))
                 '((?— . legu-ignored))))
  (should-not (legu-test--faces (legu-dired--format-cell (list :total 100 :reviewed 72 :stale 0)))))

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
