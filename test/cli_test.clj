#!/usr/bin/env bb

;; A black-box recording of legu's command line as it behaves today. Every
;; expectation here was observed by running the script, never derived from its
;; source, so the move onto babashka.cli has something that can disagree with
;; it. Where a later ticket changes an input deliberately, the case says so.
;;
;; The babashka section at the foot is the one exception, and says why.

(require '[babashka.fs :as fs]
         '[babashka.process :as p]
         '[clojure.string :as str]
         '[clojure.test :refer [deftest is run-tests]])

;; Resolved from this file rather than the working directory so the suite runs
;; the script it sits beside no matter where bb was invoked from.
(def ^:private legu
  (-> (System/getProperty "babashka.file")
      fs/absolutize fs/parent fs/parent (fs/file "legu") str))

(def ^:private reviewer "Test Reviewer")

(def ^:private fixture
  {"alpha.txt" "one\ntwo\nthree\nfour\nfive\n"
   "sub/beta.txt" "a\nb\nc\n"
   "-weird.txt" "x\n"
   "a:b.txt" "colon\nin\nname\n"})

(def ^:private scratch-dirs (atom []))

(defn- git! [dir & args]
  (let [{:keys [exit err]}
        (apply p/sh {:dir dir :out :string :err :string
                     :extra-env {"GIT_AUTHOR_DATE" "2020-01-01T00:00:00Z"
                                 "GIT_COMMITTER_DATE" "2020-01-01T00:00:00Z"}}
               "git" args)]
    (when-not (zero? exit)
      (throw (ex-info (str "git " (str/join " " args) " failed: " err) {})))))

(defn- scratch-repo!
  "Creates a committed git tree in a fresh temp directory and returns its path.
   The reviewer, the file contents and the commit dates are fixed, so nothing
   asserted about a run depends on the ambient git config or the clock."
  []
  (let [dir (str (fs/create-temp-dir {:prefix "legu-cli-test"}))]
    (swap! scratch-dirs conj dir)
    (doseq [[path content] fixture]
      (let [f (fs/file dir path)]
        (fs/create-dirs (fs/parent f))
        (spit f content)))
    (git! dir "init" "-q")
    (git! dir "config" "user.name" reviewer)
    (git! dir "config" "user.email" "reviewer@example.test")
    (git! dir "add" "-A")
    (git! dir "commit" "-qm" "initial")
    dir))

(defn- legu!
  "Runs the real script in dir and returns {:exit :out :err}. p/sh, not
   p/shell: a non-zero exit is what half these cases assert on, and p/shell
   would throw before the assertion saw it."
  [dir & args]
  (apply p/sh {:dir dir :out :string :err :string} legu args))

(defn- fails-with
  "Asserts that args exit 1 with message on stderr and nothing on stdout.
   Checking the three together keeps a case from passing on the right text and
   the wrong exit code."
  [dir args message]
  (let [{:keys [exit out err]} (apply legu! dir args)]
    (is (= [1 "" (str "legu: " message "\n")] [exit out err]) (pr-str args))))

(defn- prints-the-same-as
  "Asserts that run succeeded and printed what plain printed. The shape of
   every case pinning an option or a spelling that changes nothing a reader of
   the output can see."
  [run plain]
  (is (= [0 ""] [(:exit run) (:err run)]))
  (is (= (:out plain) (:out run))))

;; ---------------------------------------------------------------- help

(deftest no-arguments-and-help-print-the-same-usage
  (let [dir (scratch-repo!)
        bare (legu! dir)
        long-flag (legu! dir "--help")
        short-flag (legu! dir "-h")]
    (is (= [0 ""] [(:exit bare) (:err bare)]))
    (is (= [0 0] [(:exit long-flag) (:exit short-flag)]))
    (is (= (:out bare) (:out long-flag) (:out short-flag)))
    (is (str/starts-with? (:out bare) "legu — human review coverage\n"))
    ;; Pinned by the names it must contain, not verbatim: the blob itself is
    ;; regenerated when the parser moves to babashka.cli.
    (doseq [named ["mark" "ticket" "forget" "status" "regions" "stale" "next" "coverage"
                   "--json" "--version"]]
      (is (str/includes? (:out bare) named) named))
    ;; This loop asserted --reviewer, --limit, --order and --gaps here too, until
    ;; lgu-01m238wskh6s scoped each to the one command that reads it. Root help
    ;; lists what legu itself takes; the rest is a command's own help away.
    (doseq [scoped ["--reviewer" "--limit" "--order" "--gaps"]]
      (is (not (str/includes? (:out bare) scoped)) scoped))))

(deftest a-commands-help-names-its-arguments-and-only-its-own-options
  (let [dir (scratch-repo!)
        mark (:out (legu! dir "mark" "--help"))
        status (:out (legu! dir "status" "--help"))
        regions (:out (legu! dir "regions" "--help"))
        queue (:out (legu! dir "next" "--help"))
        stale (:out (legu! dir "stale" "--help"))]
    (is (str/includes? mark "Arguments:"))
    (is (str/includes? mark "<target>"))
    (is (str/includes? mark "--reviewer"))
    (is (not (str/includes? mark "--limit")))
    ;; The brackets are the whole distinction: regions needs a path, status
    ;; takes one and covers the repository without it.
    (is (str/includes? regions "<path>"))
    (is (not (str/includes? regions "[<path>]")))
    (is (str/includes? status "[<path>]"))
    (is (str/includes? status "--gaps"))
    (is (not (str/includes? status "--limit")))
    ;; An enum keeps the order it was declared in, so the default reads first.
    (is (str/includes? queue "(one of: dir, cochange)"))
    (is (not (str/includes? stale "Arguments:")))
    ;; --json is legu's own, so it survives on every page.
    (doseq [page [mark status regions queue stale]]
      (is (str/includes? page "--json") page))))

(deftest version-names-the-version-and-the-store-schema
  ;; The Emacs package parses this line for its handshake (emacs/legu.el:599),
  ;; and the literals track VERSION and sidecar-schema in legu.
  (let [{:keys [exit out err]} (legu! (scratch-repo!) "--version")]
    (is (= [0 "legu 0.4.1 (store schema 2)\n" ""] [exit out err]))))

(deftest version-in-json-carries-the-same-two-fields
  (let [dir (scratch-repo!)
        after (legu! dir "--version" "--json")
        before (legu! dir "--json" "--version")]
    ;; The space before each colon is cheshire's pretty printer, which every
    ;; --json output goes through in emit.
    (is (= "{\n  \"version\" : \"0.4.1\",\n  \"schema\" : 2\n}\n" (:out after)))
    (is (= (:out after) (:out before)))
    (is (= [0 0] [(:exit after) (:exit before)]))
    (is (= ["" ""] [(:err after) (:err before)]))))

;; ---------------------------------------------------------------- options

(deftest an-option-legu-itself-takes-may-precede-the-command
  ;; This case read --gaps on both sides until lgu-01m238wskh6s scoped it to
  ;; status. Only the options legu itself takes still stand on either side.
  (let [dir (scratch-repo!)
        before (legu! dir "--json" "status")
        after (legu! dir "status" "--json")]
    (prints-the-same-as before after)
    ;; A scoped option cannot stand before the command that scopes it, but it
    ;; is not unknown either, and the message says which command to put it on.
    (fails-with dir ["--gaps" "status"] "--gaps belongs to status, and stands after it")
    (fails-with dir ["--limit" "3" "next"] "--limit belongs to next, and stands after it")
    (fails-with dir ["--badopt" "status"] "unknown option: --badopt")))

(deftest json-false-selects-human-output
  (let [dir (scratch-repo!)
        off (legu! dir "status" "--json=false")
        plain (legu! dir "status")]
    (prints-the-same-as off plain)
    (is (not (str/starts-with? (:out off) "{")))))

(deftest a-negated-option-selects-human-output
  ;; The one spelling lgu-01m238wawfq7 changes on purpose: the hand-rolled
  ;; parser had no negation and refused --no-json, babashka.cli reads it as
  ;; {:json false}.
  (let [dir (scratch-repo!)
        off (legu! dir "--no-json" "status")
        plain (legu! dir "status")]
    (prints-the-same-as off plain)))

(deftest an-option-the-command-never-reads-is-refused
  ;; This case recorded `legu status --limit 3` printing the same status as
  ;; `legu status`, with --limit silently ignored. lgu-01m238wskh6s turns it
  ;; into an error naming the option, which is the reason that ticket exists:
  ;; a flag that did nothing gave the reader no signal.
  (let [dir (scratch-repo!)]
    (fails-with dir ["status" "--limit" "3"] "status does not take --limit")
    (fails-with dir ["next" "--gaps"] "next does not take --gaps")
    (fails-with dir ["coverage" "--reviewer" "me"] "coverage does not take --reviewer")
    (fails-with dir ["mark" "alpha.txt" "--order" "dir"] "mark does not take --order")))

(deftest an-argument-is-not-also-an-option-spelling
  ;; The dispatch tree names each command's arguments so that an option after
  ;; one is still read. Those names must not become a second way to pass the
  ;; argument: --target once slipped through, took a value legu never checked,
  ;; and dropped the real argument without an arity error.
  (let [dir (scratch-repo!)]
    (fails-with dir ["mark" "--target" "alpha.txt"] "unknown option: --target")
    (fails-with dir ["mark" "--target"] "unknown option: --target")
    (fails-with dir ["status" "--path" "sub"] "unknown option: --path")
    (fails-with dir ["ticket" "--id" "lgu-01k7"] "unknown option: --id")))

(deftest an-unknown-option-is-named-as-the-reader-typed-it
  ;; babashka.cli splits a single-dash token into one-character flags, so the
  ;; message has to find the token again in argv. Matching on the letters it
  ;; contains once named --json for a typo in -js.
  (let [dir (scratch-repo!)]
    (fails-with dir ["status" "--json" "-js"] "unknown option: -js")
    ;; --reviewer needs mark in front of it since lgu-01m238wskh6s scoped it.
    (fails-with dir ["mark" "--reviewer=me" "-r"] "unknown option: -r")))

(deftest a-value-option-refuses-an-empty-value
  ;; The command in front is lgu-01m238wskh6s: --reviewer stood alone before it
  ;; was scoped to mark. The wording is legu's, as it is for every option value.
  (let [dir (scratch-repo!)]
    (doseq [args [["mark" "alpha.txt" "--reviewer"] ["mark" "alpha.txt" "--reviewer="]]]
      (fails-with dir args "--reviewer needs a value"))))

(deftest limit-refuses-anything-but-a-positive-integer
  (let [dir (scratch-repo!)]
    ;; --limit -3 is not a missing value: -3 is consumed as the value and then
    ;; fails the positive check.
    (doseq [args [["next" "--limit" "0"] ["next" "--limit" "abc"]
                  ["next" "--limit" "-3"] ["next" "--limit=-3"]]]
      (fails-with dir args "--limit expects a positive integer"))
    (is (= 0 (:exit (legu! dir "next" "--limit" "2"))))))

(deftest order-names-the-orders-it-accepts
  (let [dir (scratch-repo!)]
    ;; dir before cochange: an enum keeps its declaration order, where the set
    ;; this replaced sorted and named cochange first.
    (fails-with dir ["next" "--order" "nope"] "--order expects one of dir, cochange")
    (is (= 0 (:exit (legu! dir "next" "--order" "cochange"))))
    (is (= 0 (:exit (legu! dir "next" "--order=dir"))))))

;; ---------------------------------------------------------------- arity

(deftest each-command-refuses-more-arguments-than-it-takes
  ;; Each line read "mark takes 1 argument, got 2" until lgu-01m238wskh6s
  ;; declared the arguments in the spec and let babashka.cli count them. The
  ;; count legu kept by hand is gone, and so is its wording.
  (let [dir (scratch-repo!)]
    (doseq [[args message] [[["mark" "a" "b"] "unexpected argument: b"]
                            [["ticket" "a" "b" "c"] "unexpected argument: c"]
                            [["forget" "a" "b"] "unexpected argument: b"]
                            [["status" "a" "b"] "unexpected argument: b"]
                            [["regions" "a" "b"] "unexpected argument: b"]
                            [["stale" "x"] "unexpected argument: x"]
                            [["next" "x"] "unexpected argument: x"]
                            [["coverage" "extra"] "unexpected argument: extra"]]]
      (fails-with dir args message))))

(deftest a-command-names-the-argument-it-is-missing
  ;; The messages read "mark needs a path", "ticket needs a path", "ticket needs
  ;; a ticket id", "forget needs a path" and "regions needs a path" until
  ;; lgu-01m238wskh6s deleted the guards that spelled them. The wording is the
  ;; library's now, and names each argument exactly as its help does.
  (let [dir (scratch-repo!)]
    (doseq [[args message] [[["mark"] "required argument: <target>"]
                            [["ticket"] "required argument: <target>"]
                            [["ticket" "alpha.txt"] "required argument: <id>"]
                            [["forget"] "required argument: <target>"]
                            [["regions"] "required argument: <path>"]]]
      (fails-with dir args message))))

(deftest a-ticket-id-typed-as-nothing-is-refused
  ;; The guard that read "ticket needs a ticket id" covered a missing id and an
  ;; empty one alike. lgu-01m238wskh6s moved both into the spec, so the empty
  ;; one has to keep failing.
  (fails-with (scratch-repo!) ["ticket" "alpha.txt" ""]
              "invalid value for argument <id>: "))

(deftest status-takes-a-path-but-does-not-need-one
  (let [dir (scratch-repo!)
        whole (legu! dir "status")
        scoped (legu! dir "status" "sub")]
    (is (= [0 ""] [(:exit whole) (:err whole)]))
    (is (= [0 ""] [(:exit scoped) (:err scoped)]))
    (is (str/includes? (:out scoped) "under sub"))))

;; ---------------------------------------------------------------- targets

(deftest a-target-may-carry-a-line-region
  (let [{:keys [exit out err]}
        (legu! (scratch-repo!) "mark" "alpha.txt:2-4" "--reviewer" reviewer)]
    (is (= [0 ""] [exit err]))
    (is (re-matches #"marked alpha\.txt:2-4 reviewed at [0-9a-f]{8}\n" out))))

(deftest a-colon-in-a-filename-is-not-a-region
  (let [dir (scratch-repo!)
        whole (legu! dir "mark" "a:b.txt" "--reviewer" reviewer)
        part (legu! dir "mark" "a:b.txt:1-2" "--reviewer" reviewer)]
    (is (re-matches #"marked a:b\.txt:1-3 reviewed at [0-9a-f]{8}\n" (:out whole)))
    (is (re-matches #"marked a:b\.txt:1-2 reviewed at [0-9a-f]{8}\n" (:out part)))))

(deftest the-terminator-carries-a-leading-hyphen-path-through
  (let [dir (scratch-repo!)
        scoped (legu! dir "status" "--" "-weird.txt")
        marked (legu! dir "mark" "--reviewer" reviewer "--" "-weird.txt")]
    (is (= [0 ""] [(:exit scoped) (:err scoped)]))
    (is (str/includes? (:out scoped) "under -weird.txt"))
    (is (= [0 ""] [(:exit marked) (:err marked)]))
    (is (re-matches #"marked -weird\.txt:1-1 reviewed at [0-9a-f]{8}\n" (:out marked)))
    ;; Without the terminator the leading hyphen reads as an option, and after
    ;; it every token is an argument — including one spelled like an option.
    (fails-with dir ["regions" "-weird.txt"] "unknown option: -weird.txt")
    (fails-with dir ["regions" "--" "-weird.txt" "--json"] "unexpected argument: --json")))

;; ---------------------------------------------------------------- errors

(deftest an-unknown-command-is-refused
  (let [dir (scratch-repo!)]
    (fails-with dir ["badcmd"] "unknown command: badcmd")
    (fails-with dir ["-"] "unknown command: -")))

(deftest an-unknown-option-is-refused-wherever-it-appears
  (let [dir (scratch-repo!)]
    (doseq [args [["--badopt"] ["status" "--badopt"] ["--badopt" "status"]]]
      (fails-with dir args "unknown option: --badopt"))))

;; ---------------------------------------------------------------- babashka

;; The only cases in this file that reach into legu instead of driving it: no
;; babashka below the floor can be installed here, so the version comparison is
;; called directly. Loading the script defines its namespace without running it
;; (see the guard at the foot of legu).
(load-file legu)

;; The namespace exists only once the load above has run, which clj-kondo does
;; not follow.
#_{:clj-kondo/ignore [:unresolved-namespace]}
(def ^:private floor legu.main/MIN-BABASHKA)

(deftest a-babashka-below-the-floor-is-refused
  (doseq [old ["1.13.219" "1.13.9" "1.12.218" "0.10.0" "1.13"]]
    (is (some? (legu.main/babashka-too-old old floor)) old)))

(deftest the-floor-itself-and-anything-newer-is-accepted
  (doseq [ok [floor "1.13.221" "1.14.0" "2.0.0" "1.13.220.1"]]
    (is (nil? (legu.main/babashka-too-old ok floor)) ok)))

(deftest a-component-is-compared-as-a-number-not-as-text
  ;; 1.13.9 sorts after 1.13.220 as a string, which is the whole reason the
  ;; comparison splits the version up.
  (is (pos? (compare "1.13.9" "1.13.220")))
  (is (some? (legu.main/babashka-too-old "1.13.9" "1.13.220"))))

(deftest a-version-string-that-does-not-parse-runs-anyway
  (doseq [odd ["1.13.220-SNAPSHOT" "dev" "" nil]]
    (is (nil? (legu.main/babashka-too-old odd floor)) (pr-str odd))))

(deftest the-message-names-both-versions-and-what-to-install
  (let [message (legu.main/babashka-too-old "1.12.218" floor)]
    (is (str/includes? message floor))
    (is (str/includes? message "1.12.218"))
    (is (str/includes? message "babashka"))
    ;; die adds the prefix and the reader is upgrading babashka, not reading a
    ;; stack trace, so neither belongs in the text.
    (is (not (str/starts-with? message "legu: ")))
    (is (not (str/ends-with? message ".")))
    (is (not (str/includes? message "babashka.cli")))))

(deftest an-older-babashka-dies-before-any-command-runs
  ;; The floor cannot be crossed by installing an older babashka here, so the
  ;; running one is told it is older than it is: -main reads the property the
  ;; same way either way, and the whole path through die is what this checks.
  (let [{:keys [exit out err]}
        (p/sh {:out :string :err :string} "bb" "-e"
              (str "(System/setProperty \"babashka.version\" \"1.12.218\")"
                   "(load-file \"" legu "\")"
                   "(legu.main/-main \"status\")"))]
    (is (= [1 ""] [exit out]))
    (is (= (str "legu: " (legu.main/babashka-too-old "1.12.218" floor) "\n") err))))

(deftest the-running-babashka-satisfies-the-floor
  (is (nil? (legu.main/babashka-too-old (System/getProperty "babashka.version") floor)))
  (is (= 0 (:exit (legu! (scratch-repo!) "--version")))))

(let [{:keys [fail error]} (try (run-tests) (finally (run! fs/delete-tree @scratch-dirs)))]
  (System/exit (if (pos? (+ fail error)) 1 0)))
