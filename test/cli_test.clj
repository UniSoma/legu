#!/usr/bin/env bb

;; A black-box recording of legu's command line as it behaves today. Every
;; expectation here was observed by running the script, never derived from its
;; source, so the move onto babashka.cli has something that can disagree with
;; it. Where a later ticket changes an input deliberately, the case says so.
;;
;; The babashka section at the foot is the one exception, and says why.

(require '[babashka.fs :as fs]
         '[babashka.process :as p]
         '[cheshire.core :as json]
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
    (is (= [0 "legu 0.4.1 (store schema 3)\n" ""] [exit out err]))))

(deftest version-in-json-carries-the-same-two-fields
  (let [dir (scratch-repo!)
        after (legu! dir "--version" "--json")
        before (legu! dir "--json" "--version")]
    ;; The space before each colon is cheshire's pretty printer, which every
    ;; --json output goes through in emit.
    (is (= "{\n  \"version\" : \"0.4.1\",\n  \"schema\" : 3\n}\n" (:out after)))
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

;; ---------------------------------------------------------------- store

;; The sidecar is the one file legu writes, and ADR-0015 fixes its bytes: a
;; header line, then one JSON object per record in a fixed key order with no
;; whitespace. These cases read the file a command left behind.

(defn- sidecar-lines
  "The lines of `path`'s sidecar under dir, or nil when there is none."
  [dir path]
  (let [f (fs/file dir ".review" (str path ".jsonl"))]
    (when (fs/exists? f) (str/split-lines (slurp f)))))

(defn- sha256 [^String s]
  (.formatHex (java.util.HexFormat/of)
              (.digest (java.security.MessageDigest/getInstance "SHA-256")
                       (.getBytes s "ISO-8859-1"))))

(def ^:private timestamp-re "\\d{4}-\\d\\d-\\d\\dT\\d\\d:\\d\\d:\\d\\dZ")

(deftest a-sidecar-is-a-header-line-and-one-json-line-per-record
  (let [dir (scratch-repo!)]
    (is (= 0 (:exit (legu! dir "mark" "alpha.txt:2-4" "--reviewer" reviewer))))
    (is (= 0 (:exit (legu! dir "ticket" "alpha.txt:3" "T-1"))))
    (let [[header record ticket & more] (sidecar-lines dir "alpha.txt")
          content (sha256 "two\nthree\nfour")
          file (sha256 (get fixture "alpha.txt"))]
      (is (nil? more))
      (is (= "{\"schema\":3}" header))
      ;; Region first, then who and when, then the evidence: the hashes are a
      ;; tail the eye skips. Timestamps are whole seconds.
      (is (re-matches (re-pattern (str "\\{\"start\":2,\"end\":4,"
                                       "\"reviewer\":\"Test Reviewer\","
                                       "\"timestamp\":\"" timestamp-re "\","
                                       "\"commit\":\"[0-9a-f]{40}\","
                                       "\"file-hash\":\"" file "\","
                                       "\"content-hash\":\"" content "\"\\}"))
                      record)
          record)
      (is (re-matches (re-pattern (str "\\{\"start\":3,\"end\":3,"
                                       "\"ticket\":\"T-1\","
                                       "\"timestamp\":\"" timestamp-re "\","
                                       "\"commit\":\"[0-9a-f]{40}\","
                                       "\"file-hash\":\"" file "\","
                                       "\"content-hash\":\"" (sha256 "three") "\"\\}"))
                      ticket)
          ticket))
    ;; Nothing is written under the name the store used before ADR-0015.
    (is (not (fs/exists? (fs/file dir ".review" "alpha.txt.edn"))))))

(deftest an-opaque-record-keeps-only-the-flag-and-the-file-hash
  (let [dir (scratch-repo!)]
    (spit (fs/file dir "empty.txt") "")
    (git! dir "add" "empty.txt")
    (git! dir "commit" "-qm" "an empty file")
    (is (= 0 (:exit (legu! dir "mark" "empty.txt" "--reviewer" reviewer))))
    (let [[_ record] (sidecar-lines dir "empty.txt")]
      (is (re-matches (re-pattern (str "\\{\"opaque\":true,"
                                       "\"reviewer\":\"Test Reviewer\","
                                       "\"timestamp\":\"" timestamp-re "\","
                                       "\"commit\":\"[0-9a-f]{40}\","
                                       "\"file-hash\":\"" (sha256 "") "\"\\}"))
                      record)
          record))))

(deftest records-are-sorted-by-region-whatever-order-they-were-made-in
  (let [dir (scratch-repo!)]
    (legu! dir "mark" "alpha.txt:4-5" "--reviewer" reviewer)
    (legu! dir "mark" "alpha.txt:1-2" "--reviewer" reviewer)
    (legu! dir "ticket" "alpha.txt:5" "T-2")
    (legu! dir "ticket" "alpha.txt:1" "T-1")
    ;; Review records before ticket references, each run sorted by region.
    (is (= ["{\"schema\":3}" "\"start\":1,\"end\":2,\"reviewer\"" "\"start\":4,\"end\":5,\"reviewer\""
            "\"start\":1,\"end\":1,\"ticket\"" "\"start\":5,\"end\":5,\"ticket\""]
           (map #(re-find #"\{\"schema\":3\}|\"start\":\d+,\"end\":\d+,\"(?:reviewer|ticket)\"" %)
                (sidecar-lines dir "alpha.txt"))))))

(deftest a-sidecar-with-nothing-left-in-it-is-removed
  (let [dir (scratch-repo!)]
    (legu! dir "mark" "alpha.txt:1-2" "--reviewer" reviewer)
    (is (some? (sidecar-lines dir "alpha.txt")))
    (is (= 0 (:exit (legu! dir "forget" "alpha.txt"))))
    (is (nil? (sidecar-lines dir "alpha.txt")))))

(defn- write-sidecar! [dir path text]
  (let [f (fs/file dir ".review" (str path ".jsonl"))]
    (fs/create-dirs (fs/parent f))
    (spit f text)))

(defn- refuses-the-sidecar
  "Asserts that a write to `path` is refused naming its sidecar, that a read
   still answers for everything else and names it under errors, and that the
   sidecar's bytes are what they were. Returns the write's stderr, for the
   caller to check the reason."
  [dir path]
  (let [f (fs/file dir ".review" (str path ".jsonl"))
        bytes (slurp f)
        {:keys [exit out err]} (legu! dir "mark" (str path ":1-1") "--reviewer" reviewer)]
    (is (= [1 ""] [exit out]))
    (is (str/starts-with? err (str "legu: cannot read " f ": ")) err)
    (let [{:keys [exit out]} (legu! dir "status" "--json")]
      (is (= 0 exit))
      (is (str/includes? out (str "\"file\" : \".review/" path ".jsonl\""))))
    (is (= bytes (slurp f)))
    err))

(deftest a-sidecar-that-does-not-parse-is-refused-whole
  (let [dir (scratch-repo!)]
    ;; A merge conflict, the way git leaves one.
    (write-sidecar! dir "alpha.txt"
                    "<<<<<<< HEAD\n{\"schema\":3}\n=======\n{\"schema\":3}\n>>>>>>> other\n")
    (refuses-the-sidecar dir "alpha.txt")
    ;; One line that does not parse, among lines that do: skipping it would
    ;; read around a conflict by dropping the records inside it.
    (write-sidecar! dir "sub/beta.txt"
                    (str "{\"schema\":3}\n"
                         "{\"start\":1,\"end\":1,\"reviewer\":\"x\",\"timestamp\":\"2026-01-01T00:00:00Z\","
                         "\"commit\":\"-\",\"file-hash\":\"a\",\"content-hash\":\"b\"}\n"
                         "{\"start\":2,\"end\":2,\"reviewer\":\"x\"\n"))
    (is (str/includes? (refuses-the-sidecar dir "sub/beta.txt") "line 3"))
    ;; A line holding a record and then something else: a conflict resolved
    ;; by hand and half-joined. The JSON parser would stop at the record and
    ;; call the line good.
    (write-sidecar! dir "alpha.txt"
                    (str "{\"schema\":3}\n"
                         "{\"start\":1,\"end\":1,\"reviewer\":\"x\",\"timestamp\":\"t\","
                         "\"commit\":\"-\",\"file-hash\":\"a\",\"content-hash\":\"b\"}>>>>>>> other\n"))
    (is (str/includes? (refuses-the-sidecar dir "alpha.txt") "line 2"))
    ;; A blank line is not a record either.
    (write-sidecar! dir "alpha.txt" "{\"schema\":3}\n\n")
    (is (str/includes? (refuses-the-sidecar dir "alpha.txt") "line 2: blank line"))))

(deftest a-sidecar-of-another-schema-is-refused-not-migrated
  (let [dir (scratch-repo!)]
    (write-sidecar! dir "alpha.txt" "{\"schema\":2}\n")
    (is (str/ends-with? (refuses-the-sidecar dir "alpha.txt")
                        "schema 2 is not the schema legu writes (3)\n"))
    ;; The header is the first line; a record there is not one.
    (write-sidecar! dir "alpha.txt"
                    "{\"start\":1,\"end\":1,\"reviewer\":\"x\",\"timestamp\":\"t\",\"commit\":\"-\",\"file-hash\":\"a\",\"content-hash\":\"b\"}\n")
    (refuses-the-sidecar dir "alpha.txt")))

(deftest a-write-names-every-sidecar-it-cannot-read-in-path-order
  ;; Many broken sidecars rather than one: each of the three writes names
  ;; every sidecar it cannot read, and drops none.
  (let [dir (scratch-repo!)
        broken (sort (concat ["-weird.txt" "a:b.txt" "sub/beta.txt"]
                             (for [i (range 40)] (format "gone/f%02d.txt" i))))
        reason "schema 2 is not the schema legu writes (3)"]
    (doseq [path broken]
      (write-sidecar! dir path "{\"schema\":2}\n"))
    (doseq [args [["mark" "alpha.txt:1-2" "--reviewer" reviewer]
                  ["ticket" "alpha.txt:1-2" "T-1"]
                  ["forget" "alpha.txt:1-2"]]]
      (let [{:keys [exit out err]} (apply legu! dir (conj args "--json"))]
        (is (= 0 exit) (pr-str args))
        (is (= (for [path broken]
                 (str "legu: cannot read " (fs/file dir ".review" (str path ".jsonl")) ": " reason))
               (str/split-lines err))
            (pr-str args))
        (is (= (for [path broken] {:file (str ".review/" path ".jsonl") :reason reason})
               (:errors (json/parse-string out true)))
            (pr-str args))))))

(deftest a-line-that-is-neither-record-nor-reference-is-refused
  (let [dir (scratch-repo!)]
    (write-sidecar! dir "alpha.txt"
                    "{\"schema\":3}\n{\"start\":1,\"end\":1,\"timestamp\":\"t\",\"commit\":\"-\",\"file-hash\":\"a\"}\n")
    (is (str/includes? (refuses-the-sidecar dir "alpha.txt") "not a review record"))
    (write-sidecar! dir "alpha.txt" "{\"schema\":3}\n[1,2,3]\n")
    (is (str/includes? (refuses-the-sidecar dir "alpha.txt") "not a review record"))))

;; ---------------------------------------------------------------- completion

;; babashka.cli derives these from the same table that parses a command line,
;; so what is worth checking is not that a snippet exists but that what it
;; offers is what legu accepts. The shells below run the snippet for real; the
;; cases before them read the callback the snippet calls.

(def ^:private shells ["bash" "zsh" "fish" "powershell" "nushell"])

;; What every drive of completion is checked against, in one place: six copies
;; of these lists meant six edits to add a command.
(def ^:private offered-commands
  ["mark" "ticket" "forget" "status" "regions" "stale" "next" "coverage"])

(def ^:private offered-options
  {"next" ["--limit" "--order" "--help" "--json" "--version"]
   "status" ["--gaps" "--help" "--json" "--version"]
   "mark" ["--reviewer" "--help" "--json" "--version"]})

(def ^:private offered-orders ["dir" "cochange"])

(defn- described
  "The candidate column of what a shell printed, one per line, with the
   description a shell shows beside it dropped."
  [out]
  (->> (str/split-lines out)
       (remove str/blank?)
       (mapv #(first (str/split % #"\t")))))

(defn- snippet
  "The init-file snippet legu emits for one shell."
  [dir shell]
  (legu! dir "org.babashka.cli/completions" "snippet" "--shell" shell))

(defn- candidates
  "What completion offers for a half-typed command line, one candidate per line
   with its description stripped. words is the line after `legu`, ending in the
   word being completed: \"\" for a fresh one."
  [dir & words]
  (let [{:keys [exit out]}
        (apply legu! dir "org.babashka.cli/completions" "complete" "--shell" "bash" "--" words)]
    (is (= 0 exit))
    (described out)))

(deftest a-snippet-is-emitted-for-every-shell-legu-names
  (let [dir (scratch-repo!)]
    (doseq [shell shells
            :let [{:keys [exit out err]} (snippet dir shell)]]
      (is (= [0 ""] [exit err]) shell)
      (is (str/includes? out "org.babashka.cli/completions complete") shell)
      (is (str/includes? out "legu") shell))))

(deftest completion-offers-the-command-names
  (let [dir (scratch-repo!)]
    (is (= offered-commands (candidates dir "")))))

(deftest completion-offers-only-the-options-the-command-takes
  (let [dir (scratch-repo!)]
    (doseq [[command expected] offered-options]
      (is (= expected (candidates dir command "--")) command))
    ;; The claim under all three: nothing offered is anything the command would
    ;; turn down. An option legu has elsewhere is refused by name, so a wrong
    ;; candidate shows up here as that refusal rather than as a missing flag.
    (doseq [command (keys offered-options)
            candidate (candidates dir command "--")
            :let [{:keys [err]} (legu! dir command candidate "x")]]
      (is (not (str/includes? err "does not take")) (str command " " candidate)))))

(deftest completion-offers-the-orders-next-accepts
  (let [dir (scratch-repo!)]
    (is (= offered-orders (candidates dir "next" "--order" "")))))

(defn- shell-path
  "The directory the driven shells find legu in. The snippet completes the word
   the reader types, and resolves the script from it, so the script has to be
   reachable under its own name."
  [dir]
  (let [bin (fs/file dir "bin")]
    (fs/create-dirs bin)
    (when-not (fs/exists? (fs/file bin "legu"))
      (fs/create-sym-link (fs/file bin "legu") legu))
    (str bin)))

(defn- shell-env [dir]
  {"PATH" (str (shell-path dir) java.io.File/pathSeparator (System/getenv "PATH"))
   ;; fish and zsh both write under $HOME on startup, and the home of whoever
   ;; runs the suite is not the suite's to write to.
   "HOME" dir})

(defn- installed?
  "Whether the shell is there to be driven. A missing one fails rather than
   skipping: completion is unchecked either way, and a skip that reports green
   is indistinguishable from a shell that answered."
  [shell]
  (or (some? (fs/which shell))
      (do (is false (str "no " shell " on PATH, so its completion went unchecked"))
          false)))

(deftest bash-completes-a-command-line-through-the-snippet
  (when (installed? "bash")
    (let [dir (scratch-repo!)
          driver (fs/file dir "drive.bash")]
      (spit (fs/file dir "snippet.bash") (:out (snippet dir "bash")))
      ;; The snippet registers a function against the word `legu`; calling it
      ;; with the words and the cursor bash would have set is what pressing TAB
      ;; does. --norc keeps whatever the runner has in ~/.bashrc out of it.
      (spit driver (str "source \"$HOME/snippet.bash\"\n"
                        "COMP_WORDS=(\"$@\"); COMP_CWORD=$(( $# - 1 )); COMPREPLY=()\n"
                        "_babashka_cli_complete_legu\n"
                        "printf '%s\\n' \"${COMPREPLY[@]}\"\n"))
      (let [offered (fn [& words]
                      (let [{:keys [exit out]}
                            (apply p/sh {:dir dir :out :string :err :string
                                         :extra-env (shell-env dir)}
                                   "bash" "--norc" "--noprofile" (str driver) "legu" words)]
                        (is (= 0 exit))
                        (described out)))]
        (is (= offered-commands (offered "")))
        (doseq [[command expected] offered-options]
          (is (= expected (offered command "--")) command))
        (is (= offered-orders (offered "next" "--order" "")))))))

(deftest fish-completes-a-command-line-through-the-snippet
  (when (installed? "fish")
    (let [dir (scratch-repo!)
          autoloaded (fs/file dir ".config" "fish" "completions" "legu.fish")]
      ;; The snippet goes where the README puts it: the directory fish reads a
      ;; command's completions from without being told to.
      (fs/create-dirs (fs/parent autoloaded))
      (spit autoloaded (:out (snippet dir "fish")))
      ;; complete -C asks fish for the candidates it would show for a line,
      ;; through the same machinery a TAB goes through.
      (let [offered (fn [line]
                      (let [{:keys [exit out]}
                            (p/sh {:dir dir :out :string :err :string
                                   :extra-env (shell-env dir)}
                                  "fish" "-c" (str "complete -C '" line "'"))]
                        (is (= 0 exit))
                        (->> (str/split-lines out)
                             (remove str/blank?)
                             (mapv #(first (str/split % #"\t"))))))]
        (is (= ["mark" "ticket" "forget" "status" "regions" "stale" "next" "coverage"]
               (offered "legu ")))
        (is (= ["--limit" "--order" "--help" "--json" "--version"] (offered "legu next --")))
        (is (= ["--gaps" "--help" "--json" "--version"] (offered "legu status --")))
        (is (= ["dir" "cochange"] (offered "legu next --order ")))))))

(deftest zsh-completes-a-command-line-through-the-snippet
  (when (installed? "zsh")
    (let [dir (scratch-repo!)
          driver (str (fs/file (fs/parent legu) "test" "complete_in_zsh.zsh"))]
      (spit (fs/file dir "snippet.zsh") (:out (snippet dir "zsh")))
      ;; The snippet goes where a reader is told to put it: an init file the
      ;; interactive shell reads at startup.
      (spit (fs/file dir ".zshrc")
            (str "autoload -Uz compinit; compinit -u -D\n"
                 "unsetopt beep\n"
                 "source " (fs/file dir "snippet.zsh") "\n"))
      (let [offered (fn [line]
                      (let [{:keys [exit out]}
                            (p/sh {:dir dir :out :string :err :string
                                   :extra-env (shell-env dir)}
                                  "zsh" "-f" driver line)]
                        (is (= 0 exit) line)
                        ;; zsh paints a menu rather than printing a list, so
                        ;; these are substring checks. An empty screen would
                        ;; satisfy every "does not offer" among them, so it is
                        ;; ruled out once, here.
                        (is (not (str/blank? out)) line)
                        out))]
        (let [names (offered "legu ")]
          (doseq [named offered-commands]
            (is (str/includes? names named) named)))
        (doseq [[command expected] offered-options
                :let [painted (offered (str "legu " command " --"))]]
          (doseq [named expected]
            (is (str/includes? painted named) (str command " " named)))
          ;; The point of the ticket: an option another command owns is not
          ;; offered for this one.
          (doseq [absent (remove (set expected) (distinct (apply concat (vals offered-options))))]
            (is (not (str/includes? painted absent)) (str command " " absent))))
        (let [orders (offered "legu next --order ")]
          (doseq [order offered-orders]
            (is (str/includes? orders order) order)))))))

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

(deftest the-same-state-renders-as-the-same-bytes
  ;; Called directly: through the command line every record carries the second
  ;; it was made in, so two orders of the same marks cannot be compared byte
  ;; for byte. The literal is the layout ADR-0015 fixes.
  (let [render #'legu.main/render-sidecar
        a {:start 10 :end 20 :reviewer "a \"quoted\" name" :timestamp "2026-08-28T10:00:28Z"
           :commit "c439a988" :file-hash "be9c" :content-hash "d65c"}
        b {:start 1 :end 5 :reviewer "b" :timestamp "2026-08-28T10:00:28Z"
           :commit "c439a988" :file-hash "be9c" :content-hash "0000"}
        ;; An opaque record made from a region still carries nil bounds.
        o {:opaque true :start nil :end nil :content-hash nil
           :ticket "lgu-01k7" :timestamp "2026-08-28T10:00:29Z" :commit "c439a988" :file-hash "be9c"}
        t {:start 1 :end 1 :ticket "T-1" :timestamp "2026-08-28T10:00:29Z"
           :commit "c439a988" :file-hash "be9c" :content-hash "0000"}
        expected (str "{\"schema\":3}\n"
                      "{\"start\":1,\"end\":5,\"reviewer\":\"b\",\"timestamp\":\"2026-08-28T10:00:28Z\",\"commit\":\"c439a988\",\"file-hash\":\"be9c\",\"content-hash\":\"0000\"}\n"
                      "{\"start\":10,\"end\":20,\"reviewer\":\"a \\\"quoted\\\" name\",\"timestamp\":\"2026-08-28T10:00:28Z\",\"commit\":\"c439a988\",\"file-hash\":\"be9c\",\"content-hash\":\"d65c\"}\n"
                      "{\"opaque\":true,\"ticket\":\"lgu-01k7\",\"timestamp\":\"2026-08-28T10:00:29Z\",\"commit\":\"c439a988\",\"file-hash\":\"be9c\"}\n"
                      "{\"start\":1,\"end\":1,\"ticket\":\"T-1\",\"timestamp\":\"2026-08-28T10:00:29Z\",\"commit\":\"c439a988\",\"file-hash\":\"be9c\",\"content-hash\":\"0000\"}\n")]
    (is (= expected (render {:regions [a b] :tickets [o t]})))
    (is (= expected (render {:regions [b a] :tickets [t o]})))))

(let [{:keys [fail error]} (try (run-tests) (finally (run! fs/delete-tree @scratch-dirs)))]
  (System/exit (if (pos? (+ fail error)) 1 0)))
