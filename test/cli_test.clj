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

(defn- write-files!
  "Writes each path to content under dir, creating parent directories."
  [dir files]
  (doseq [[path content] files]
    (let [f (fs/file dir path)]
      (fs/create-dirs (fs/parent f))
      (spit f content))))

(defn- scratch-dir!
  "A fresh temp directory, registered for cleanup, with no git in it."
  []
  (let [dir (str (fs/create-temp-dir {:prefix "legu-cli-test"}))]
    (swap! scratch-dirs conj dir)
    dir))

(defn- scratch-repo!
  "Creates a committed git tree in a fresh temp directory and returns its path.
   The reviewer, the file contents and the commit dates are fixed, so nothing
   asserted about a run depends on the ambient git config or the clock."
  []
  (let [dir (scratch-dir!)]
    (write-files! dir fixture)
    (git! dir "init" "-q")
    (git! dir "config" "user.name" reviewer)
    (git! dir "config" "user.email" "reviewer@example.test")
    (git! dir "add" "-A")
    (git! dir "commit" "-qm" "initial")
    dir))

(defn- config-home
  "The XDG_CONFIG_HOME every run of legu gets, inside the scratch tree: a case
   that reached the real one would read or overwrite the signing key of
   whoever runs the suite."
  [dir]
  (str (fs/file dir ".config")))

(defn- legu!
  "Runs the real script in dir and returns {:exit :out :err}. p/sh, not
   p/shell: a non-zero exit is what half these cases assert on, and p/shell
   would throw before the assertion saw it."
  [dir & args]
  (apply p/sh {:dir dir :out :string :err :string
               :extra-env {"XDG_CONFIG_HOME" (config-home dir)}}
         legu args))

(defn- store-snapshot
  "Every file under dir's .review/, as a map of relative path to content."
  [dir]
  (let [store (fs/file dir ".review")]
    (into (sorted-map)
          (for [f (file-seq store) :when (.isFile f)]
            [(str (fs/relativize store f)) (slurp f)]))))

(defn- fails-with
  "Asserts that args exit 1 with message on stderr and nothing on stdout, and
   leave the store as it was: a command that cannot land changes nothing.
   Checking these together keeps a case from passing on the right text and
   the wrong exit code."
  [dir args message]
  (let [before (store-snapshot dir)
        {:keys [exit out err]} (apply legu! dir args)]
    (is (= [1 "" (str "legu: " message "\n")] [exit out err]) (pr-str args))
    (is (= before (store-snapshot dir)) (str (pr-str args) " changed the store"))))

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
                   "key" "verify" "--json" "--version"]]
      (is (str/includes? (:out bare) named) named))
    ;; key is one line at the root; its subcommands are a `legu key --help` away.
    (doseq [subcommand ["init" "show" "add"]]
      (is (not (re-find (re-pattern (str "(?m)^  " subcommand " ")) (:out bare))) subcommand))
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
        stale (:out (legu! dir "stale" "--help"))
        verify (:out (legu! dir "verify" "--help"))]
    (is (str/includes? mark "Arguments:"))
    (is (str/includes? mark "<target>"))
    (is (str/includes? mark "--reviewer"))
    (is (not (str/includes? mark "--limit")))
    ;; The brackets are the whole distinction: regions needs a path, status
    ;; takes one and covers the repository without it.
    (is (str/includes? regions "<path>"))
    (is (not (str/includes? regions "[<path>]")))
    (is (str/includes? status "[<path>]"))
    (is (str/includes? verify "[<path>]"))
    (is (not (str/includes? verify "--reviewer")))
    (is (str/includes? status "--gaps"))
    (is (not (str/includes? status "--limit")))
    ;; An enum keeps the order it was declared in, so the default reads first.
    (is (str/includes? queue "(one of: dir, cochange)"))
    (is (not (str/includes? stale "Arguments:")))
    ;; --json is legu's own, so it survives on every page.
    (doseq [page [mark status regions queue stale verify]]
      (is (str/includes? page "--json") page))))

(deftest key-lists-its-subcommands-with-or-without-help
  (let [dir (scratch-repo!)
        bare (legu! dir "key")
        help (legu! dir "key" "--help")
        init (legu! dir "key" "init" "--help")]
    (is (= [0 ""] [(:exit bare) (:err bare)]))
    (is (= [0 0] [(:exit help) (:exit init)]))
    (is (= (:out bare) (:out help)))
    (is (str/includes? (:out help) "Usage: legu key"))
    (doseq [subcommand ["init" "show" "add"]]
      (is (re-find (re-pattern (str "(?m)^  " subcommand " ")) (:out help)) subcommand))
    (is (str/includes? (:out init) "Usage: legu key init"))
    (is (str/includes? (:out init) "--json"))
    (is (not (str/includes? (:out init) "--reviewer")))))

(deftest mark-and-coverage-describe-themselves-in-the-glossarys-words
  ;; lgu-01m23d9faenk: mark's help said "reviewed at HEAD" and coverage's said
  ;; "never-read", against ADR-0006 and CONTEXT.md. HEAD is only the commit a
  ;; record cites; what was read is the working tree.
  (let [dir (scratch-repo!)
        mark (:out (legu! dir "mark" "--help"))
        coverage (:out (legu! dir "coverage" "--help"))]
    (is (str/includes? mark "mark a region reviewed as it stands in the working tree"))
    (is (not (str/includes? mark "HEAD")))
    (is (str/includes? coverage "unreviewed / reviewed / stale"))
    (is (not (str/includes? coverage "never")))))

(deftest coverage-rows-and-json-keys-say-the-same-three-states
  ;; lgu-01m23d9faenk renamed the never-read row and JSON key, and the read row,
  ;; to the glossary's words: the key now matches what status and next emit.
  (let [dir (scratch-repo!)
        _ (legu! dir "mark" "alpha.txt:1-2")
        human (legu! dir "coverage")
        machine (legu! dir "coverage" "--json")]
    (is (= [0 0] [(:exit human) (:exit machine)]))
    (is (re-find #"(?m)^  unreviewed +10 " (:out human)))
    (is (re-find #"(?m)^  reviewed +2 " (:out human)))
    (is (re-find #"(?m)^  stale +0 " (:out human)))
    (is (not (re-find #"never|(?m)^  read " (:out human))))
    (is (= {"eligible-files" 4 "eligible-lines" 12 "unreviewed" 10 "reviewed" 2 "stale" 0}
           (json/parse-string (:out machine))))))

(deftest status-and-next-tables-say-the-glossarys-words
  ;; lgu-01m26gbjmqjc: the tables headed their columns READ, UNREAD and READ
  ;; RANGES and called a file "read in full", words CONTEXT.md avoids for the
  ;; reviewed and unreviewed states. No JSON key moved.
  (let [dir (scratch-repo!)
        _ (legu! dir "mark" "alpha.txt:1-2")
        _ (legu! dir "mark" "sub/beta.txt")
        status (legu! dir "status")
        queue (legu! dir "next")
        machine (json/parse-string (:out (legu! dir "status" "--json")))]
    (is (= [0 0] [(:exit status) (:exit queue)]))
    (is (re-find #"(?m)^FILES  3 with gaps · 1 fully reviewed$" (:out status)))
    (is (re-find #"(?m)^  PATH +REVIEWED  STALE  UNREVIEWED  TOTAL  REVIEWED RANGES$" (:out status)))
    (is (re-find #"(?m)^  sub/beta\.txt +3 +0 +0 +3  fully reviewed$" (:out status)))
    (is (re-find #"(?m)^  PATH +UNREVIEWED  STALE  TO READ$" (:out queue)))
    (is (not (re-find #"UNREAD|READ RANGES|read in full|  READ  " (str (:out status) (:out queue)))))
    (is (= #{"path" "total" "reviewed" "stale" "unreviewed" "ranges"}
           (set (mapcat keys (get machine "files")))))))

(deftest version-names-the-version-and-the-store-schema
  ;; The Emacs package parses this line for its handshake (emacs/legu.el:599),
  ;; and the literals track VERSION and sidecar-schema in legu.
  (let [{:keys [exit out err]} (legu! (scratch-repo!) "--version")]
    (is (= [0 "legu 0.5.0 (store schema 4)\n" ""] [exit out err]))))

(deftest version-in-json-carries-the-same-two-fields
  (let [dir (scratch-repo!)
        after (legu! dir "--version" "--json")
        before (legu! dir "--json" "--version")]
    ;; The space before each colon is cheshire's pretty printer, which every
    ;; --json output goes through in emit.
    (is (= "{\n  \"version\" : \"0.5.0\",\n  \"schema\" : 4\n}\n" (:out after)))
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
    (fails-with dir ["mark" "alpha.txt" "--order" "dir"] "mark does not take --order")
    ;; A subcommand is named by its whole path: `init does not take` would
    ;; leave the reader to guess which init.
    (fails-with dir ["key" "init" "--reviewer" "me"] "key init does not take --reviewer")
    (fails-with dir ["key" "--limit" "3"] "key does not take --limit")))

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
                            [["coverage" "extra"] "unexpected argument: extra"]
                            [["key" "init" "extra"] "unexpected argument: extra"]
                            [["key" "show" "extra"] "unexpected argument: extra"]
                            [["key" "add" "extra"] "unexpected argument: extra"]
                            [["verify" "a" "b"] "unexpected argument: b"]]]
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
    (fails-with dir ["-"] "unknown command: -")
    (fails-with dir ["key" "bogus"] "unknown command: key bogus")))

(deftest an-unknown-option-is-refused-wherever-it-appears
  (let [dir (scratch-repo!)]
    (doseq [args [["--badopt"] ["status" "--badopt"] ["--badopt" "status"]]]
      (fails-with dir args "unknown option: --badopt"))))

;; ---------------------------------------------------------------- store

;; The sidecar is the one file legu writes, and ADR-0015 fixes its bytes: a
;; header line, then one JSON object per record in a fixed key order with no
;; whitespace. These cases read the file a command left behind.

(defn- sidecar-rel
  "Where `path`'s sidecar lives relative to the repo root, as legu names it in
   messages and `errors`. ADR-0017 puts the sidecars one level down the store."
  [path]
  (str ".review/sidecars/" path ".jsonl"))

(defn- sidecar-file [dir path]
  (fs/file dir (sidecar-rel path)))

(defn- sidecar-lines
  "The lines of `path`'s sidecar under dir, or nil when there is none."
  [dir path]
  (let [f (sidecar-file dir path)]
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
      (is (= "{\"schema\":4}" header))
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
    (is (= ["{\"schema\":4}" "\"start\":1,\"end\":2,\"reviewer\"" "\"start\":4,\"end\":5,\"reviewer\""
            "\"start\":1,\"end\":1,\"ticket\"" "\"start\":5,\"end\":5,\"ticket\""]
           (map #(re-find #"\{\"schema\":4\}|\"start\":\d+,\"end\":\d+,\"(?:reviewer|ticket)\"" %)
                (sidecar-lines dir "alpha.txt"))))))

(deftest a-sidecar-with-nothing-left-in-it-is-removed
  (let [dir (scratch-repo!)]
    (legu! dir "mark" "alpha.txt:1-2" "--reviewer" reviewer)
    (is (some? (sidecar-lines dir "alpha.txt")))
    (is (= 0 (:exit (legu! dir "forget" "alpha.txt"))))
    (is (nil? (sidecar-lines dir "alpha.txt")))))

;; Forget acts on whole records (ADR-0018). A range inside one matches
;; nothing, and a forget that drops nothing fails rather than answering
;; "forgot 0" with exit 0, which every caller read as success.

(deftest a-forget-inside-a-record-fails-and-names-the-record
  (let [dir (scratch-repo!)]
    (legu! dir "mark" "alpha.txt:1-5" "--reviewer" reviewer)
    (let [before (sidecar-lines dir "alpha.txt")
          {:keys [exit out err]} (legu! dir "forget" "alpha.txt:2-3")]
      (is (= 1 exit))
      (is (= "" out))
      (is (= "legu: no record anchored at alpha.txt:2-3; records covering it: alpha.txt:1-5\n"
             err))
      (is (= before (sidecar-lines dir "alpha.txt"))))))

(deftest a-forget-across-two-records-names-both
  (let [dir (scratch-repo!)]
    (legu! dir "mark" "alpha.txt:1-2" "--reviewer" reviewer)
    (legu! dir "mark" "alpha.txt:3-5" "--reviewer" reviewer)
    (legu! dir "ticket" "alpha.txt:4-4" "T-1")
    (let [{:keys [exit err]} (legu! dir "forget" "alpha.txt:2-4")]
      (is (= 1 exit))
      (is (= (str "legu: no record anchored at alpha.txt:2-4; records overlapping it: "
                  "alpha.txt:1-2, alpha.txt:3-5, alpha.txt:4-4\n")
             err)))))

(deftest a-forget-that-drops-nothing-fails
  (let [dir (scratch-repo!)]
    (doseq [target ["alpha.txt" "alpha.txt:1-2"]]
      (let [{:keys [exit out err]} (legu! dir "forget" target "--json")]
        (is (= 1 exit) target)
        (is (= "" out) target)
        (is (= (str "legu: nothing to forget at " target "\n") err) target)))
    (is (nil? (sidecar-lines dir "alpha.txt")))))

(defn- write-sidecar! [dir path text]
  (let [f (sidecar-file dir path)]
    (fs/create-dirs (fs/parent f))
    (spit f text)))

(defn- refuses-the-sidecar
  "Asserts that a write to `path` is refused naming its sidecar, that a read
   still answers for everything else and names it under errors, and that the
   sidecar's bytes are what they were. Returns the write's stderr, for the
   caller to check the reason."
  [dir path]
  (let [f (sidecar-file dir path)
        bytes (slurp f)
        {:keys [exit out err]} (legu! dir "mark" (str path ":1-1") "--reviewer" reviewer)]
    (is (= [1 ""] [exit out]))
    (is (str/starts-with? err (str "legu: cannot read " f ": ")) err)
    (let [{:keys [exit out]} (legu! dir "status" "--json")]
      (is (= 0 exit))
      (is (str/includes? out (str "\"file\" : \"" (sidecar-rel path) "\""))))
    (is (= bytes (slurp f)))
    err))

(deftest a-sidecar-that-does-not-parse-is-refused-whole
  (let [dir (scratch-repo!)]
    ;; A merge conflict, the way git leaves one.
    (write-sidecar! dir "alpha.txt"
                    "<<<<<<< HEAD\n{\"schema\":4}\n=======\n{\"schema\":4}\n>>>>>>> other\n")
    (refuses-the-sidecar dir "alpha.txt")
    ;; One line that does not parse, among lines that do: skipping it would
    ;; read around a conflict by dropping the records inside it.
    (write-sidecar! dir "sub/beta.txt"
                    (str "{\"schema\":4}\n"
                         "{\"start\":1,\"end\":1,\"reviewer\":\"x\",\"timestamp\":\"2026-01-01T00:00:00Z\","
                         "\"commit\":\"-\",\"file-hash\":\"a\",\"content-hash\":\"b\"}\n"
                         "{\"start\":2,\"end\":2,\"reviewer\":\"x\"\n"))
    (is (str/includes? (refuses-the-sidecar dir "sub/beta.txt") "line 3"))
    ;; A line holding a record and then something else: a conflict resolved
    ;; by hand and half-joined. The JSON parser would stop at the record and
    ;; call the line good.
    (write-sidecar! dir "alpha.txt"
                    (str "{\"schema\":4}\n"
                         "{\"start\":1,\"end\":1,\"reviewer\":\"x\",\"timestamp\":\"t\","
                         "\"commit\":\"-\",\"file-hash\":\"a\",\"content-hash\":\"b\"}>>>>>>> other\n"))
    (is (str/includes? (refuses-the-sidecar dir "alpha.txt") "line 2"))
    ;; A blank line is not a record either.
    (write-sidecar! dir "alpha.txt" "{\"schema\":4}\n\n")
    (is (str/includes? (refuses-the-sidecar dir "alpha.txt") "line 2: blank line"))))

(deftest a-sidecar-of-another-schema-is-refused-not-migrated
  ;; lgu-01m28srsmekn moved legu to schema 4, so schema 3 is the older one.
  (let [dir (scratch-repo!)]
    (write-sidecar! dir "alpha.txt" "{\"schema\":3}\n")
    (is (str/ends-with? (refuses-the-sidecar dir "alpha.txt")
                        "schema 3 is not the schema legu writes (4)\n"))
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
        reason "schema 3 is not the schema legu writes (4)"]
    (doseq [path broken]
      (write-sidecar! dir path "{\"schema\":3}\n"))
    (doseq [args [["mark" "alpha.txt:1-2" "--reviewer" reviewer]
                  ["ticket" "alpha.txt:1-2" "T-1"]
                  ["forget" "alpha.txt:1-2"]]]
      (let [{:keys [exit out err]} (apply legu! dir (conj args "--json"))]
        (is (= 0 exit) (pr-str args))
        (is (= (for [path broken]
                 (str "legu: cannot read " (sidecar-file dir path) ": " reason))
               (str/split-lines err))
            (pr-str args))
        (is (= (for [path broken] {:file (sidecar-rel path) :reason reason})
               (:errors (json/parse-string out true)))
            (pr-str args))))))

(deftest a-line-that-is-neither-record-nor-reference-is-refused
  (let [dir (scratch-repo!)]
    (write-sidecar! dir "alpha.txt"
                    "{\"schema\":4}\n{\"start\":1,\"end\":1,\"timestamp\":\"t\",\"commit\":\"-\",\"file-hash\":\"a\"}\n")
    (is (str/includes? (refuses-the-sidecar dir "alpha.txt") "not a review record"))
    (write-sidecar! dir "alpha.txt" "{\"schema\":4}\n[1,2,3]\n")
    (is (str/includes? (refuses-the-sidecar dir "alpha.txt") "not a review record"))))

;; ---------------------------------------------------------------- store layout

;; ADR-0017: the store holds everything legu owns. The sidecars mirror the
;; source tree under sidecars/, and the ignore list sits at the store's root.

(defn- commit! [dir files]
  (write-files! dir files)
  (apply git! dir "add" "--" (keys files))
  (git! dir "commit" "-qm" "layout"))

(defn- regions-json [dir path]
  (json/parse-string (:out (legu! dir "regions" path "--json")) true))

(defn- coverage-json [dir]
  (json/parse-string (:out (legu! dir "coverage" "--json")) true))

(deftest a-mark-writes-its-sidecar-under-the-sidecars-directory
  (let [dir (scratch-repo!)]
    (is (= 0 (:exit (legu! dir "mark" "alpha.txt:1-2" "--reviewer" reviewer))))
    (is (= 0 (:exit (legu! dir "mark" "sub/beta.txt" "--reviewer" reviewer))))
    (is (fs/regular-file? (fs/file dir ".review/sidecars/alpha.txt.jsonl")))
    (is (fs/regular-file? (fs/file dir ".review/sidecars/sub/beta.txt.jsonl")))
    (is (not (fs/exists? (fs/file dir ".review/alpha.txt.jsonl"))))
    (is (= [[1 2]] (map (juxt :start :end) (:regions (regions-json dir "alpha.txt")))))))

(deftest the-ignore-list-is-read-from-the-store
  (let [dir (scratch-repo!)]
    (commit! dir {".review/ignore" "sub/\n"})
    (let [beta (regions-json dir "sub/beta.txt")]
      (is (= [false "excluded by .review/ignore"]
             [(:eligible beta) (:exclusion-reason beta)])))
    ;; The fixture's 12 lines less beta's 3.
    (is (= 9 (:eligible-lines (coverage-json dir))))
    (let [{:keys [exit err]} (legu! dir "mark" "sub/beta.txt" "--reviewer" reviewer)]
      (is (= 0 exit))
      (is (= (str "legu: sub/beta.txt is excluded by .review/ignore"
                  " and will not count toward coverage\n")
             err)))))

(deftest a-reviewignore-at-the-repo-root-is-an-ordinary-file
  (let [dir (scratch-repo!)]
    (commit! dir {".reviewignore" "sub/\n"})
    (is (:eligible (regions-json dir "sub/beta.txt")))
    (is (:eligible (regions-json dir ".reviewignore")))))

(deftest a-file-at-the-stores-root-is-never-eligible
  (let [dir (scratch-repo!)]
    (commit! dir {".review/ignore" "# nothing ignored\n"
                  ".review/notes.txt" "not a sidecar\n"})
    (doseq [path [".review/ignore" ".review/notes.txt"]]
      (let [data (regions-json dir path)]
        (is (= [false "legu metadata"] [(:eligible data) (:exclusion-reason data)])
            path)))
    (is (= 12 (:eligible-lines (coverage-json dir))))))

;; ------------------------------------------------------- blobs at commits

;; A record's file as it was at the commit it cites comes from one
;; `git cat-file --batch` process per run. The framing is the whole risk: each
;; blob arrives behind a header line and ahead of a newline the reader has to
;; step over, so a case below gives the batch an empty blob, a blob holding a
;; line shaped like a header, and a commit with no such object at all.

(defn- stale-json [dir]
  (json/parse-string (:out (legu! dir "stale" "--json")) true))

(defn- anchors [dir path]
  (for [r (:regions (regions-json dir path))]
    [(:start r) (:end r) (:state r) (:reason r) (:moved r)]))

(defn- framing-repo!
  "A repo whose three records need three kinds of blob read at their commit:
   an empty one, one git has no object for, and one holding a line shaped like
   a cat-file header. They are read in path order, so the two that frame
   oddly come first and a frame either of them mis-sizes takes the third
   with it. The twin in twin.txt is the discriminating one: its
   region is rewritten in the working tree and survives elsewhere, so legu
   reports it stale only if the old text it read says the block already had a
   twin at review time."
  []
  (let [dir (scratch-repo!)
        twin (str "one\ntwo\ndeadbeef blob 7\nthree\n"
                  "filler\n"
                  "one\ntwo\ndeadbeef blob 7\nthree\n")]
    (commit! dir {"empty.txt" "" "twin.txt" twin})
    (write-files! dir {"empty.txt" "alpha\nbeta\ngamma\n"
                       "new.txt" "n1\nn2\nn3\n"})
    (doseq [target ["empty.txt:1-2" "twin.txt:1-4" "new.txt:1-2"]]
      (legu! dir "mark" target "--reviewer" reviewer))
    (write-files! dir {"empty.txt" "alpha\nbeta\ngamma\ndelta\n"
                       "twin.txt" "zzz\nfiller\none\ntwo\ndeadbeef blob 7\nthree\n"
                       "new.txt" "top\nn1\nn2\nn3\n"})
    dir))

(deftest reading-files-at-their-commits-spawns-one-batched-git-process
  (let [dir (framing-repo!)
        ;; under .git so the log is not a file of the tree legu reports on
        log (str (fs/file dir ".git" "git-trace.log"))
        _ (apply p/sh {:dir dir :out :string :err :string
                       :extra-env {"XDG_CONFIG_HOME" (config-home dir)
                                   "GIT_TRACE" log}}
                 legu ["stale" "--json"])
        lines (str/split-lines (slurp log))]
    (is (= 1 (count (filter #(str/includes? % "cat-file --batch") lines))))
    (is (= [] (filterv #(str/includes? % "git show ") lines)))))

(deftest an-empty-a-missing-and-a-header-shaped-blob-all-come-out-whole
  (let [dir (framing-repo!)]
    (is (= [[1 2 "reviewed" "block moved" true]] (anchors dir "empty.txt")))
    ;; ADR-0018: the four reviewed lines were rewritten as the one line
    ;; "zzz", so the hunk's one new line is what went stale.
    (is (= [[1 1 "stale" "content changed" false]] (anchors dir "twin.txt")))
    (is (= [[2 3 "reviewed" "block moved" true]] (anchors dir "new.txt")))
    (is (= [{:path "twin.txt" :start 1 :end 1
             :reason "content changed" :state "stale"}]
           (:stale (stale-json dir))))))

(deftest records-across-two-commits-each-anchor-at-their-own-commit
  (let [dir (scratch-repo!)
        lines (fn [& ls] (str (str/join "\n" ls) "\n"))]
    (commit! dir {"one.txt" (lines "a1" "a2" "a3")
                  "two.txt" (lines "b1" "b2" "b3")})
    (doseq [target ["one.txt:1-2" "two.txt:2-3"]]
      (legu! dir "mark" target "--reviewer" reviewer))
    (commit! dir {"one.txt" (lines "head" "a1" "a2" "a3")
                  "three.txt" (lines "c1" "c2" "c3")})
    ;; one.txt:1-2 at this commit is "head","a1" — a different region from the
    ;; record above, which anchors at 2-3 now, so both survive and the same
    ;; path is read at two commits.
    (doseq [target ["one.txt:1-2" "three.txt:1-2"]]
      (legu! dir "mark" target "--reviewer" reviewer))
    ;; every file grows a line above the marks, each record shifting by what
    ;; changed since its own commit
    (write-files! dir {"one.txt" (lines "top" "head" "a1" "a2" "a3")
                       "two.txt" (lines "top" "b1" "b2" "b3")
                       "three.txt" (lines "top" "c1" "c2" "c3")})
    (is (= [[2 3 "reviewed" nil true] [3 4 "reviewed" nil true]]
           (anchors dir "one.txt")))
    (is (= [[3 4 "reviewed" nil true]] (anchors dir "two.txt")))
    (is (= [[2 3 "reviewed" nil true]] (anchors dir "three.txt")))
    (is (= [] (:stale (stale-json dir))))
    ;; Now edit inside every marked range, so each record is confirmed against
    ;; its own commit's text and fragmented against it. A blob read for the
    ;; wrong commit or the wrong path fails that confirmation, and the record
    ;; falls back to whole-region stale instead.
    (write-files! dir {"one.txt" (lines "top" "head" "a1" "a2 edited" "a3")
                       "two.txt" (lines "top" "b1" "b2 edited" "b3")
                       "three.txt" (lines "top" "c1" "c2 edited" "c3")})
    ;; The 1-2 record of the second commit is "head","a1", which the edit
    ;; below it leaves whole; the 1-2 record of the first commit is "a1","a2",
    ;; which it splits.
    (is (= [[2 3 "reviewed" nil true]
            [3 3 "reviewed" nil true]
            [4 4 "stale" "content changed" false]]
           (anchors dir "one.txt")))
    (is (= [[3 3 "stale" "content changed" false]
            [4 4 "reviewed" nil true]]
           (anchors dir "two.txt")))
    (is (= [[2 2 "reviewed" nil true]
            [3 3 "stale" "content changed" false]]
           (anchors dir "three.txt")))))

;; ---------------------------------------------------------------- staleness

;; ADR-0018: once a record is confirmed against the file at the commit it
;; cites, the lines each hunk touched are stale and the lines between the
;; hunks stay reviewed where they landed. A case here names an edit and
;; asserts the ranges and states reported for it, never the ladder that
;; found them.

(defn- numbered
  "Lines `from`..`to`, each naming itself under `word`, so a reported range
   can be read straight off the file it came from."
  ([from to] (numbered "line" from to))
  ([word from to]
   (str/join (for [n (range from (inc to))] (str word " " n "\n")))))

(defn- status-json [dir]
  (json/parse-string (:out (legu! dir "status" "--json")) true))

(defn- next-json [dir]
  (json/parse-string (:out (legu! dir "next" "--json")) true))

(defn- file-row [dir path]
  (first (filter #(= path (:path %)) (:files (status-json dir)))))

(defn- long-record!
  "A repository whose long.txt is 150 numbered lines, with a record over each
   of `targets`, or over the whole file when none is named."
  [& targets]
  (let [dir (scratch-repo!)]
    (commit! dir {"long.txt" (numbered 1 150)})
    (doseq [target (or (seq targets) ["long.txt:1-150"])]
      (legu! dir "mark" target "--reviewer" reviewer))
    dir))

(defn- edit-73-97!
  "Rewrite long.txt's lines 73-97 in place, leaving 1-72 and 98-150 as read."
  [dir]
  (write-files! dir {"long.txt" (str (numbered 1 72) (numbered "edit" 73 97)
                                     (numbered 98 150))}))

(deftest an-edit-inside-a-region-leaves-only-the-edited-lines-stale
  (let [dir (long-record!)]
    (edit-73-97! dir)
    (is (= [[1 72 "reviewed" nil false]
            [73 97 "stale" "content changed" false]
            [98 150 "reviewed" nil false]]
           (anchors dir "long.txt")))
    (is (= [{:path "long.txt" :start 73 :end 97
             :reason "content changed" :state "stale"}]
           (:stale (stale-json dir))))
    (is (= {:path "long.txt" :total 150 :reviewed 125 :stale 25 :unreviewed 0
            :ranges "1-72,98-150"}
           (file-row dir "long.txt")))
    (is (= "73-97" (:ranges (first (filter #(= "long.txt" (:path %))
                                           (:next (next-json dir)))))))))

(deftest two-edits-in-one-region-leave-one-stale-fragment-each
  (let [dir (long-record!)]
    (write-files! dir {"long.txt" (str (numbered 1 19) (numbered "edit" 20 21)
                                       (numbered 22 59) (numbered "edit" 60 61)
                                       (numbered 62 150))})
    (is (= [[1 19 "reviewed" nil false]
            [20 21 "stale" "content changed" false]
            [22 59 "reviewed" nil false]
            [60 61 "stale" "content changed" false]
            [62 150 "reviewed" nil false]]
           (anchors dir "long.txt")))
    (is (= [{:path "long.txt" :start 20 :end 21
             :reason "content changed" :state "stale"}
            {:path "long.txt" :start 60 :end 61
             :reason "content changed" :state "stale"}]
           (:stale (stale-json dir))))
    (is (= {:path "long.txt" :total 150 :reviewed 146 :stale 4 :unreviewed 0
            :ranges "1-19,22-59,62-150"}
           (file-row dir "long.txt")))))

(deftest a-mark-over-part-of-a-stale-fragment-leaves-the-rest-stale
  (let [dir (long-record!)]
    (edit-73-97! dir)
    (legu! dir "mark" "long.txt:73-80" "--reviewer" reviewer)
    ;; Staleness is per line: `stale` names what is left, the same lines
    ;; `status` and `next` count.
    (is (= [{:path "long.txt" :start 81 :end 97
             :reason "content changed" :state "stale"}]
           (:stale (stale-json dir))))
    (is (= {:path "long.txt" :total 150 :reviewed 133 :stale 17 :unreviewed 0
            :ranges "1-80,98-150"}
           (file-row dir "long.txt")))
    (is (= "81-97" (:ranges (first (filter #(= "long.txt" (:path %))
                                           (:next (next-json dir)))))))))

(deftest an-edit-that-grows-or-shrinks-moves-the-lines-below-it
  (doseq [[replacement stale-end below-start] [[(numbered "edit" 1 30) 102 103]
                                               [(numbered "edit" 1 20) 92 93]]]
    (let [dir (long-record!)]
      (write-files! dir {"long.txt" (str (numbered 1 72) replacement
                                         (numbered 98 150))})
      (is (= [[1 72 "reviewed" nil false]
              [73 stale-end "stale" "content changed" false]
              [below-start (+ below-start 52) "reviewed" nil true]]
             (anchors dir "long.txt"))
          (str "stale through line " stale-end)))))

(deftest an-insertion-inside-a-region-leaves-the-lines-below-it-reviewed
  (let [dir (long-record!)]
    (write-files! dir {"long.txt" (str (numbered 1 80) (numbered "added" 1 3)
                                       (numbered 81 150))})
    (is (= [[1 80 "reviewed" nil false]
            [81 83 "stale" "content changed" false]
            [84 153 "reviewed" nil true]]
           (anchors dir "long.txt")))
    (is (= [{:path "long.txt" :start 81 :end 83
             :reason "content changed" :state "stale"}]
           (:stale (stale-json dir))))
    ;; every piece names the one record it came from
    (is (= [{:path "long.txt" :start 1 :end 150 :commit nil :timestamp nil
             :reviewer reviewer}]
           (distinct (for [r (:regions (regions-json dir "long.txt"))]
                       (-> (:original r)
                           (assoc :commit nil :timestamp nil))))))))

(deftest an-edit-outside-a-region-leaves-the-whole-record-reviewed
  (doseq [[what file] [["above" (str (numbered "edit" 1 12) (numbered 13 150))]
                       ["right before" (str (numbered 1 49) (numbered "added" 1 2)
                                            (numbered 50 150))]
                       ["right after" (str (numbered 1 100) (numbered "added" 1 2)
                                           (numbered 101 150))]]]
    (let [dir (long-record! "long.txt:50-100")]
      (write-files! dir {"long.txt" file})
      (is (= (if (= "right before" what)
               [[52 102 "reviewed" nil true]]
               [[50 100 "reviewed" nil false]])
             (anchors dir "long.txt"))
          what))))

(deftest marking-the-stale-lines-again-clears-them-and-keeps-both-records
  (let [dir (long-record!)]
    (edit-73-97! dir)
    (is (= 0 (:exit (legu! dir "mark" "long.txt:73-97" "--reviewer" reviewer))))
    (is (= [] (:stale (stale-json dir))))
    (is (= [150 0 0] ((juxt :reviewed :stale :unreviewed) (file-row dir "long.txt"))))
    ;; the old record still answers for the 125 lines nobody read again, and
    ;; still says the hunk changed under it: the new record is what reviews
    ;; those lines, by the rule that a reviewed line beats a stale one
    (is (= [[1 72 "reviewed"] [73 97 "stale"] [73 97 "reviewed"]
            [98 150 "reviewed"]]
           (map #(take 3 %) (anchors dir "long.txt"))))
    (is (= 2 (count (rest (sidecar-lines dir "long.txt")))))))

(deftest a-deletion-inside-a-region-leaves-one-stale-line-at-the-seam
  (let [dir (long-record!)]
    (write-files! dir {"long.txt" (str (numbered 1 72) (numbered 98 150))})
    ;; the line the deletion left behind is the one that reads differently now
    (is (= [[1 72 "reviewed" nil false]
            [73 73 "stale" "content changed" false]
            [74 125 "reviewed" nil true]]
           (anchors dir "long.txt")))
    (is (= [{:path "long.txt" :start 73 :end 73
             :reason "content changed" :state "stale"}]
           (:stale (stale-json dir))))
    (is (= {:path "long.txt" :total 125 :reviewed 124 :stale 1 :unreviewed 0
            :ranges "1-72,74-125"}
           (file-row dir "long.txt")))))

(deftest a-deletion-at-the-end-of-a-region-seams-on-its-last-remaining-line
  (let [dir (long-record! "long.txt:50-100")]
    ;; no line after the deletion is left inside the region, so the seam falls
    ;; on the line before it, and the record claims nothing below itself
    (write-files! dir {"long.txt" (str (numbered 1 89) (numbered 101 150))})
    (is (= [[50 88 "reviewed" nil false]
            [89 89 "stale" "content changed" false]]
           (anchors dir "long.txt")))
    (is (= {:path "long.txt" :total 139 :reviewed 39 :stale 1 :unreviewed 99
            :ranges "50-88"}
           (file-row dir "long.txt")))))

(deftest deleting-every-line-of-a-region-leaves-it-stale-where-it-was
  (let [dir (long-record! "long.txt:50-100")]
    ;; nothing is left of the region to seam on, so it is stale at the range
    ;; it was read at, clamped to the file
    (write-files! dir {"long.txt" (str (numbered 1 49) (numbered 101 150))})
    (is (= [[50 99 "stale" "content changed" false]] (anchors dir "long.txt")))
    (is (= [{:path "long.txt" :start 50 :end 99
             :reason "content changed" :state "stale"}]
           (:stale (stale-json dir))))))

(deftest part-of-a-region-cut-and-pasted-elsewhere-seams-and-lands-unreviewed
  (let [dir (long-record! "long.txt:40-100")]
    ;; only the whole region is evidence, so the block carries no review with
    ;; it: a seam where it was cut, and unreviewed lines where it landed
    (write-files! dir {"long.txt" (str (numbered 1 72) (numbered 98 129)
                                       (numbered 73 97) (numbered 130 150))})
    (is (= [[40 72 "reviewed" nil false]
            [73 73 "stale" "content changed" false]
            [74 75 "reviewed" nil true]]
           (anchors dir "long.txt")))
    (is (= {:path "long.txt" :total 150 :reviewed 35 :stale 1 :unreviewed 114
            :ranges "40-72,74-75"}
           (file-row dir "long.txt")))))

(deftest an-edit-crossing-the-region-start-is-stale-from-the-clipped-start
  (let [dir (long-record! "long.txt:73-150")]
    ;; the edit runs from line 60 to line 80, but the record read it only from
    ;; 73 on, so it answers for the last eight of those lines and nothing
    ;; above: 1-72 was never read and stays unreviewed
    (write-files! dir {"long.txt" (str (numbered 1 59) (numbered "edit" 60 80)
                                       (numbered 81 150))})
    (is (= [[73 80 "stale" "content changed" false]
            [81 150 "reviewed" nil false]]
           (anchors dir "long.txt")))
    (is (= [{:path "long.txt" :start 73 :end 80
             :reason "content changed" :state "stale"}]
           (:stale (stale-json dir))))
    (is (= {:path "long.txt" :total 150 :reviewed 70 :stale 8 :unreviewed 72
            :ranges "81-150"}
           (file-row dir "long.txt")))))

(deftest an-edit-crossing-the-region-end-is-stale-to-its-projected-end
  (let [dir (long-record! "long.txt:50-100")]
    ;; three lines above the region move it down, so the end it answers to is
    ;; 103, not the 100 it was read at; the edit writes as far as 118 and the
    ;; record claims none of that tail
    (write-files! dir {"long.txt" (str (numbered "top" 1 3) (numbered 1 89)
                                       (numbered "edit" 1 26)
                                       (numbered 111 150))})
    (is (= [[53 92 "reviewed" nil true]
            [93 103 "stale" "content changed" false]]
           (anchors dir "long.txt")))
    (is (= [{:path "long.txt" :start 93 :end 103
             :reason "content changed" :state "stale"}]
           (:stale (stale-json dir))))
    (is (= {:path "long.txt" :total 158 :reviewed 40 :stale 11 :unreviewed 107
            :ranges "53-92"}
           (file-row dir "long.txt")))))

(deftest a-crossing-edit-that-shrank-below-the-offset-leaves-one-seam-line
  (let [dir (long-record! "long.txt:73-150")]
    ;; the record entered the edit thirteen lines in and the edit wrote only
    ;; five, so nothing it wrote is the record's to claim: the line after it
    ;; is the seam, as it is for a deletion
    (write-files! dir {"long.txt" (str (numbered 1 59) (numbered "edit" 1 5)
                                       (numbered 81 150))})
    (is (= [[65 65 "stale" "content changed" false]
            [66 134 "reviewed" nil true]]
           (anchors dir "long.txt")))
    (is (= [{:path "long.txt" :start 65 :end 65
             :reason "content changed" :state "stale"}]
           (:stale (stale-json dir))))
    (is (= {:path "long.txt" :total 134 :reviewed 69 :stale 1 :unreviewed 64
            :ranges "66-134"}
           (file-row dir "long.txt")))))

(deftest two-records-crossed-by-one-edit-each-claim-their-own-part-of-it
  (let [dir (long-record! "long.txt:1-50" "long.txt:51-100")]
    ;; one edit over 40-60 crosses the seam between the two records: the first
    ;; read eleven of its old lines and the second the other ten, so the first
    ;; claims the edit's first eleven new lines and the second the rest —
    ;; 40-65 covered once over, no line claimed twice and none dropped
    (write-files! dir {"long.txt" (str (numbered 1 39) (numbered "edit" 1 26)
                                       (numbered 61 150))})
    (is (= [[1 39 "reviewed" nil false]
            [40 50 "stale" "content changed" false]
            [51 65 "stale" "content changed" false]
            [66 105 "reviewed" nil true]]
           (anchors dir "long.txt")))
    (is (= [{:path "long.txt" :start 40 :end 50
             :reason "content changed" :state "stale"}
            {:path "long.txt" :start 51 :end 65
             :reason "content changed" :state "stale"}]
           (:stale (stale-json dir))))
    (is (= {:path "long.txt" :total 155 :reviewed 79 :stale 26 :unreviewed 50
            :ranges "1-39,66-105"}
           (file-row dir "long.txt")))))

(deftest a-region-cut-and-pasted-elsewhere-in-its-file-is-moved-not-stale
  (let [dir (long-record! "long.txt:50-60")]
    (write-files! dir {"long.txt" (str (numbered 1 49) (numbered 61 150)
                                       (numbered 50 60))})
    (is (= [[140 150 "reviewed" "block moved" true]] (anchors dir "long.txt")))
    (is (= [] (:stale (stale-json dir))))))

(deftest a-ticket-reference-reports-its-whole-region-not-the-hunk
  (let [dir (long-record!)]
    (legu! dir "ticket" "long.txt:1-150" "T-1")
    (edit-73-97! dir)
    (let [data (regions-json dir "long.txt")]
      (is (= 3 (count (:regions data))))
      (is (= [{:start 1 :end 150 :state "stale" :ticket "T-1"}]
             (map #(select-keys % [:start :end :state :ticket]) (:tickets data)))))))

(deftest a-record-no-commit-confirms-goes-stale-whole
  (let [dir (scratch-repo!)]
    (commit! dir {"long.txt" (numbered 1 150)})
    ;; the mark reads a working tree the commit it cites never held, so the
    ;; diff against that commit is no evidence about what was read
    (write-files! dir {"long.txt" (str (numbered 1 40) (numbered "draft" 1 5)
                                       (numbered 41 150))})
    (legu! dir "mark" "long.txt:1-155" "--reviewer" reviewer)
    (write-files! dir {"long.txt" (str (numbered 1 40) (numbered "draft" 1 5)
                                       (numbered 41 99) (numbered "edit" 100 101)
                                       (numbered 102 150))})
    (is (= ["stale"] (map #(nth % 2) (anchors dir "long.txt"))))))

(deftest a-store-with-no-git-reports-the-whole-region-stale
  (let [dir (scratch-dir!)]
    (write-files! dir {"long.txt" (numbered 1 150)})
    (is (= 0 (:exit (legu! dir "mark" "long.txt:1-150" "--reviewer" reviewer))))
    (edit-73-97! dir)
    (is (= [[1 150 "stale" "content changed" false]] (anchors dir "long.txt")))))

;; ------------------------------------------------------- relative indentation

;; ADR-0019: trailing whitespace never matters and leading whitespace matters
;; relative to the region. Two texts are the same read when, after removing the
;; leading whitespace common to every line of each, they trim equal at the end
;; of each line. The fixtures below are Python, where the indentation carries
;; the meaning a reader of the region signed for.

(def ^:private totals-py
  (str "def head(rows):\n"
       "    return rows[0]\n"
       "\n"
       "def totals(rows):\n"
       "    total = 0\n"
       "    for row in rows:\n"
       "        total += row.amount\n"
       "    return total\n"))

(defn- totals-repo!
  "A repo whose totals.py holds two functions, the second of them, lines 4-8,
   read and marked. An edit to `head` is then an edit outside the region and
   inside the same file."
  []
  (let [dir (scratch-repo!)]
    (commit! dir {"totals.py" totals-py})
    (legu! dir "mark" "totals.py:4-8" "--reviewer" reviewer)
    dir))

(deftest a-line-dedented-out-of-its-block-is-stale
  (let [dir (totals-repo!)]
    ;; the accumulation leaves the loop with no other character touched, so its
    ;; offset from the lines around it changed and it alone is stale
    (write-files! dir {"totals.py" (str/replace totals-py
                                               "        total += row.amount"
                                               "    total += row.amount")})
    (is (= [[4 6 "reviewed" nil false]
            [7 7 "stale" "content changed" false]
            [8 8 "reviewed" nil false]]
           (anchors dir "totals.py")))
    (is (= [{:path "totals.py" :start 7 :end 7
             :reason "content changed" :state "stale"}]
           (:stale (stale-json dir))))))

(defn- indented
  "`text` with every line from `from` on given four more spaces, as wrapping
   them in a new block would leave them."
  [text from]
  (str/join (map-indexed (fn [i l] (str (when (>= (inc i) from) "    ") l "\n"))
                         (str/split-lines text))))

(defn- longer-head
  "totals.py with two lines added to `head`, which is outside the marked
   region and moves it down the file."
  [text]
  (str/replace text "    return rows[0]\n"
               "    if not rows:\n        return None\n    return rows[0]\n"))

(deftest a-block-reindented-together-stays-reviewed
  (let [dir (totals-repo!)]
    (write-files! dir {"totals.py" (indented totals-py 4)})
    (is (= [[4 8 "reviewed" nil false]] (anchors dir "totals.py")))
    (is (= [] (:stale (stale-json dir))))))

(deftest a-block-reindented-beside-an-edit-in-its-file-stays-reviewed
  (let [dir (totals-repo!)]
    ;; the edit to `head` moves the region two lines down the file, so the
    ;; lines the indentation is judged against are the ones it landed on
    (write-files! dir {"totals.py" (indented (longer-head totals-py) 6)})
    (is (= [[6 10 "reviewed" nil true]] (anchors dir "totals.py")))
    (is (= [] (:stale (stale-json dir))))))

(deftest wrapping-a-block-in-a-new-if-leaves-only-the-inserted-line-stale
  (let [dir (totals-repo!)]
    (write-files! dir {"totals.py" (str/replace (indented totals-py 5)
                                                "def totals(rows):\n"
                                                "def totals(rows):\n    if rows:\n")})
    (is (= [[4 4 "reviewed" nil false]
            [5 5 "stale" "content changed" false]
            [6 9 "reviewed" nil true]]
           (anchors dir "totals.py")))
    (is (= [{:path "totals.py" :start 5 :end 5
             :reason "content changed" :state "stale"}]
           (:stale (stale-json dir))))))

(deftest trailing-whitespace-a-crlf-flip-and-a-lost-last-newline-are-no-change
  (let [dir (totals-repo!)]
    (write-files! dir {"totals.py" (-> totals-py
                                       (str/replace "    total = 0\n" "    total = 0  \n")
                                       (str/replace "\n" "\r\n")
                                       (str/replace #"\r\n$" ""))})
    (is (= [[4 8 "reviewed" nil false]] (anchors dir "totals.py")))
    (is (= [] (:stale (stale-json dir))))))

(def ^:private tabbed-py
  (str "def totals(rows):\n"
       "\ttotal = 0\n"
       "\tfor row in rows:\n"
       "\t\ttotal += row.amount\n"
       "\treturn total\n"))

(deftest tabs-converted-to-spaces-are-stale
  (let [dir (scratch-repo!)]
    (commit! dir {"tabbed.py" tabbed-py})
    (legu! dir "mark" "tabbed.py:1-5" "--reviewer" reviewer)
    ;; a tab and four spaces are different characters, so the nesting inside
    ;; the loop lands at a different offset from the lines around it: a
    ;; reformat, which ADR-0003 already calls stale. A file indented at one
    ;; level throughout would be a uniform shift and stay reviewed, which is
    ;; why the fixture nests.
    (write-files! dir {"tabbed.py" (str/replace tabbed-py "\t" "    ")})
    (is (= [[1 1 "reviewed" nil false]
            [2 5 "stale" "content changed" false]]
           (anchors dir "tabbed.py")))
    (is (= [{:path "tabbed.py" :start 2 :end 5
             :reason "content changed" :state "stale"}]
           (:stale (stale-json dir))))))

(deftest a-record-no-commit-confirms-keeps-the-trim-alone
  (let [dir (scratch-repo!)]
    ;; the mark reads a working tree the commit it cites never held, so no text
    ;; says how the lines it read were laid out and the trim is all there is
    (commit! dir {"totals.py" (str/replace totals-py "    total = 0" "    total = 1")})
    (write-files! dir {"totals.py" totals-py})
    (legu! dir "mark" "totals.py:4-8" "--reviewer" reviewer)
    (write-files! dir {"totals.py" (str/replace totals-py
                                                "        total += row.amount"
                                                "    total += row.amount")})
    (is (= [[4 8 "reviewed" nil false]] (anchors dir "totals.py")))))

(deftest a-line-dedented-inside-a-block-that-moved-is-the-only-stale-one
  (let [dir (totals-repo!)]
    ;; the whole function went a level deeper and the accumulation came a level
    ;; back out of the loop: the block moved together and only the line that
    ;; left it changed its offset from the rest
    (write-files! dir {"totals.py" (str/replace (indented totals-py 4)
                                                "            total += row.amount"
                                                "        total += row.amount")})
    (is (= [[4 6 "reviewed" nil false]
            [7 7 "stale" "content changed" false]
            [8 8 "reviewed" nil false]]
           (anchors dir "totals.py")))))

(deftest a-block-reindented-beside-an-edit-inside-the-region-stays-reviewed
  (let [dir (totals-repo!)]
    ;; the edit and the reindent land in one hunk, and what the wrap shares
    ;; with what it replaced comes off it: only the edited line is stale
    (write-files! dir {"totals.py" (-> totals-py
                                       (str/replace "    total = 0" "    total = 1")
                                       (indented 6))})
    (is (= [[4 4 "reviewed" nil false]
            [5 5 "stale" "content changed" false]
            [6 8 "reviewed" nil false]]
           (anchors dir "totals.py")))))

;; ------------------------------------------------------- marks on a dirty tree

;; ADR-0018: a mark made on a dirty working tree cites a commit whose text it
;; did not read, so the commits after it that touched the path are tried in
;; order and the first that confirms the record's hash is diffed against. The
;; search is capped; past the cap the record falls back to whole-region stale,
;; as does one citing a commit git does not have.

(def ^:private drafted
  "long.txt as the working tree held it when it was marked: five draft lines
   between line 40 and line 41 of the committed text, so `numbered` line n
   below the drafts sits at line n+5."
  (str (numbered 1 40) (numbered "draft" 1 5) (numbered 41 150)))

(defn- dirty-mark!
  "A repo whose long.txt was marked whole while the five draft lines were
   still uncommitted, so the commit the record cites does not hold the text
   it read."
  []
  (let [dir (scratch-repo!)]
    (commit! dir {"long.txt" (numbered 1 150)})
    (write-files! dir {"long.txt" drafted})
    (legu! dir "mark" "long.txt:1-155" "--reviewer" reviewer)
    dir))

(defn- edited-at
  "`drafted` with the `numbered` lines `from`..`to` rewritten."
  [from to]
  (str (numbered 1 40) (numbered "draft" 1 5) (numbered 41 (dec from))
       (numbered "edit" from to) (numbered (inc to) 150)))

(deftest a-mark-taken-on-a-dirty-tree-fragments-against-the-commit-that-follows
  (let [dir (dirty-mark!)]
    (commit! dir {"long.txt" drafted})
    (write-files! dir {"long.txt" (edited-at 100 101)})
    (is (= [[1 104 "reviewed" nil false]
            [105 106 "stale" "content changed" false]
            [107 155 "reviewed" nil false]]
           (anchors dir "long.txt")))
    (is (= [{:path "long.txt" :start 105 :end 106
             :reason "content changed" :state "stale"}]
           (:stale (stale-json dir))))))

(deftest the-search-passes-a-later-commit-that-does-not-confirm
  (let [dir (dirty-mark!)]
    ;; the commit right after the mark holds the drafts but not the text that
    ;; was read; the one after it holds it exactly
    (commit! dir {"long.txt" (edited-at 60 60)})
    (commit! dir {"long.txt" drafted})
    (write-files! dir {"long.txt" (edited-at 100 101)})
    (is (= [[1 104 "reviewed" nil false]
            [105 106 "stale" "content changed" false]
            [107 155 "reviewed" nil false]]
           (anchors dir "long.txt")))))

(deftest the-first-confirming-commit-is-what-the-record-is-diffed-against
  (let [dir (dirty-mark!)]
    ;; Two commits confirm, and the diff is taken from the first: what the
    ;; second one changed inside the region is stale, because nobody read it.
    ;; Diffing against HEAD instead would report only the working-tree edit.
    ;; Which of two confirming commits was used is otherwise unobservable —
    ;; both hold the same text, so both give the same fragments.
    (commit! dir {"long.txt" drafted})
    (commit! dir {"long.txt" (edited-at 60 60)})
    (write-files! dir {"long.txt" (str (numbered 1 40) (numbered "draft" 1 5)
                                       (numbered 41 59) (numbered "edit" 60 60)
                                       (numbered 61 99) (numbered "edit" 100 101)
                                       (numbered 102 150))})
    (is (= [[1 64 "reviewed" nil false]
            [65 65 "stale" "content changed" false]
            [66 104 "reviewed" nil false]
            [105 106 "stale" "content changed" false]
            [107 155 "reviewed" nil false]]
           (anchors dir "long.txt")))))

(deftest a-record-citing-a-commit-git-does-not-have-goes-stale-whole
  (let [dir (dirty-mark!)
        sidecar (fs/file dir ".review" "sidecars" "long.txt.jsonl")]
    (commit! dir {"long.txt" drafted})
    ;; nothing can be searched forward from a commit that is not in the repo
    (spit sidecar (str/replace (slurp sidecar) #"\"commit\":\"[0-9a-f]+\""
                               "\"commit\":\"0000000000000000000000000000000000000000\""))
    (write-files! dir {"long.txt" (edited-at 100 101)})
    (is (= [[1 155 "stale" "content changed" false]] (anchors dir "long.txt")))))

(deftest the-forward-search-stops-after-a-few-commits
  (let [dir (dirty-mark!)]
    ;; Six commits touch the path and only the last holds what was read. The
    ;; cap in legu is five, so the search never reaches it and the record
    ;; falls back to whole-region stale; a case above proves a commit inside
    ;; the cap is found. Raising the cap in legu makes this case pass wrongly,
    ;; so it moves with it.
    (doseq [n (range 60 65)]
      (commit! dir {"long.txt" (edited-at n n)}))
    (commit! dir {"long.txt" drafted})
    (write-files! dir {"long.txt" (edited-at 100 101)})
    (is (= [[1 155 "stale" "content changed" false]] (anchors dir "long.txt")))
    ;; The commits the search may try are found before any blob is read, so
    ;; the five candidates are asked for in the batch the record's own commit
    ;; is: one log, one batch, and no file read on its own.
    (let [log (str (fs/file dir ".git" "git-trace.log"))
          _ (apply p/sh {:dir dir :out :string :err :string
                         :extra-env {"XDG_CONFIG_HOME" (config-home dir)
                                     "GIT_TRACE" log}}
                   legu ["stale" "--json"])
          lines (str/split-lines (slurp log))
          runs (fn [cmd] (count (filter #(str/includes? % cmd) lines)))]
      (is (= [1 1 0] [(runs "log --reverse")
                      (runs "cat-file --batch")
                      (runs "git show ")])))))

;; ---------------------------------------------------------------- keys

;; ADR-0016: each user signs with a key kept under their config directory, and
;; a store lists the keys it trusts in .review/signers. legu! points
;; XDG_CONFIG_HOME inside the scratch tree, so every key below is made there.

(defn- key-file [dir name]
  (fs/file (config-home dir) "legu" name))

(def ^:private base64-32-bytes #"[A-Za-z0-9+/]{43}=\n")

(deftest key-init-writes-an-owner-only-seed-and-its-public-half
  (let [dir (scratch-repo!)
        {:keys [exit out err]} (legu! dir "key" "init")
        private (key-file dir "key")
        public (key-file dir "key.pub")]
    (is (= [0 ""] [exit err]))
    (is (= (str "created " private " and " public "\n") out))
    (is (re-matches base64-32-bytes (slurp private)))
    (is (re-matches base64-32-bytes (slurp public)))
    (is (not= (slurp private) (slurp public)))
    (is (= "rw-------" (fs/posix->str (fs/posix-file-permissions private))))))

(deftest key-init-falls-back-to-config-under-home
  ;; HOME points into the scratch tree, so the fallback never reaches the
  ;; developer's own ~/.config.
  (let [dir (scratch-repo!)
        home (str (fs/file dir "home"))
        {:keys [exit err]} (p/sh {:dir dir :out :string :err :string
                                  :extra-env {"XDG_CONFIG_HOME" "" "HOME" home}}
                                 legu "key" "init")]
    (is (= [0 ""] [exit err]))
    (is (fs/exists? (fs/file home ".config" "legu" "key")))
    (is (fs/exists? (fs/file home ".config" "legu" "key.pub")))))

(deftest key-init-refuses-to-replace-a-key
  (let [dir (scratch-repo!)
        _ (legu! dir "key" "init")
        private (key-file dir "key")
        before [(slurp private) (slurp (key-file dir "key.pub"))]]
    (fails-with dir ["key" "init"]
                (str "a signing key already exists at " private
                     "; legu key init never replaces one"))
    (is (= before [(slurp private) (slurp (key-file dir "key.pub"))]))))

(defn- public-key [dir]
  (str/trim (slurp (key-file dir "key.pub"))))

(deftest key-show-prints-the-signers-line-for-the-key
  (let [dir (scratch-repo!)
        _ (legu! dir "key" "init")
        {:keys [exit out err]} (legu! dir "key" "show")]
    (is (= [0 ""] [exit err]))
    (is (= (str (public-key dir) " " reviewer "\n") out))))

(deftest key-show-and-add-need-a-key-and-a-name
  (let [dir (scratch-repo!)
        no-key (str "no signing key at " (key-file dir "key.pub")
                    "; create one with legu key init")]
    (fails-with dir ["key" "show"] no-key)
    (fails-with dir ["key" "add"] no-key)
    (legu! dir "key" "init")
    ;; Set empty rather than unset: the repo's own value hides any global one
    ;; the machine running the suite has.
    (git! dir "config" "user.name" "")
    (doseq [command ["show" "add"]]
      (fails-with dir ["key" command]
                  "git config user.name is not set, and the signers list names the key after it; set it with git config user.name <name>"))
    (is (not (fs/exists? (fs/file dir ".review" "signers"))))))

(defn- signers-text [dir]
  (let [f (fs/file dir ".review" "signers")]
    (when (fs/exists? f) (slurp f))))

(deftest key-add-creates-the-signers-list-and-adds-a-key-once
  (let [dir (scratch-repo!)
        _ (legu! dir "key" "init")
        line (str (public-key dir) " " reviewer)
        first-run (legu! dir "key" "add")
        written (signers-text dir)
        second-run (legu! dir "key" "add")]
    (is (= [0 "" (str "added to .review/signers: " line "\n")]
           ((juxt :exit :err :out) first-run)))
    (is (= (str line "\n") written))
    (is (= [0 "" (str ".review/signers already lists: " line "\n")]
           ((juxt :exit :err :out) second-run)))
    (is (= written (signers-text dir)))
    ;; key show prints the line key add writes.
    (is (= (str line "\n") (:out (legu! dir "key" "show"))))))

(deftest key-add-refuses-a-key-listed-under-another-name
  (let [dir (scratch-repo!)
        _ (legu! dir "key" "init")
        _ (legu! dir "key" "add")
        before (signers-text dir)]
    (git! dir "config" "user.name" "Someone Else")
    (fails-with dir ["key" "add"] ".review/signers already lists this key as Test Reviewer")
    (is (= before (signers-text dir)))))

(deftest key-add-appends-past-comments-blank-lines-and-other-keys
  ;; A name may own several keys, so another key under the same name is no
  ;; conflict. A comment naming this key under another name is not a binding,
  ;; and a line that is not a binding at all is left for verify to report.
  (let [dir (scratch-repo!)
        _ (legu! dir "key" "init")
        key (public-key dir)
        existing (str "# who may sign\n"
                      "# " key " Mallory\n"
                      "\n"
                      "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA= " reviewer "\n"
                      "not-a-binding\n"
                      "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB= Someone Else")
        _ (write-files! dir {".review/signers" existing})
        {:keys [exit err]} (legu! dir "key" "add")]
    (is (= [0 ""] [exit err]))
    ;; The last line had no newline, so key add supplies one before its own.
    (is (= (str existing "\n" key " " reviewer "\n") (signers-text dir)))))

(deftest each-key-subcommand-answers-in-json
  (let [dir (scratch-repo!)
        run (fn [& args]
              (let [{:keys [exit out err]} (apply legu! dir (conj (vec args) "--json"))]
                (is (= [0 ""] [exit err]) (pr-str args))
                (json/parse-string out)))
        init (run "key" "init")
        key (public-key dir)]
    (is (= {"private-key-file" (str (key-file dir "key"))
            "public-key-file" (str (key-file dir "key.pub"))
            "public-key" key}
           init))
    (is (= {"public-key" key "reviewer" reviewer "line" (str key " " reviewer)}
           (run "key" "show")))
    (is (= {"file" ".review/signers" "public-key" key "reviewer" reviewer "added" true}
           (run "key" "add")))
    (is (= {"file" ".review/signers" "public-key" key "reviewer" reviewer "added" false}
           (run "key" "add")))))

;; ------------------------------------------------------- signed review records

;; ADR-0016: a store with a signers list is signed, and mark signs each review
;; record with the local key under the name the list gives it.

(def ^:private listed-elsewhere
  "A binding for a key no scratch tree holds."
  "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA= Someone Else\n")

(defn- list-key!
  "Creates the scratch tree's key and a signers list binding it to `name`.
   Returns the public key."
  [dir name]
  (legu! dir "key" "init")
  (let [key (public-key dir)]
    (write-files! dir {".review/signers" (str key " " name "\n")})
    key))

(defn- alpha-2-4
  "A pattern for the review record of alpha.txt:2-4 under `name`, with
   `signature` as its last key when given."
  [name signature]
  (re-pattern (str "\\{\"start\":2,\"end\":4,"
                   "\"reviewer\":\"" name "\","
                   "\"timestamp\":\"" timestamp-re "\","
                   "\"commit\":\"[0-9a-f]{40}\","
                   "\"file-hash\":\"" (sha256 (get fixture "alpha.txt")) "\","
                   "\"content-hash\":\"" (sha256 "two\nthree\nfour") "\""
                   (when signature (str ",\"signature\":\"" signature "\""))
                   "\\}")))

(def ^:private base64-64-bytes "[A-Za-z0-9+/]{86}==")

(defn- verifies?
  "Whether the signature ending `line` holds for the base64 `public-key` over
   the bytes the README documents: legu-review-record, a newline, then the
   line without its signature key. Built from the JDK and the README alone,
   so it can disagree with legu's renderer."
  [public-key line]
  (let [[_ unsigned signature] (re-matches #"(.*),\"signature\":\"([^\"]*)\"\}" line)
        decode #(.decode (java.util.Base64/getDecoder) ^String %)
        ;; The X.509 header of an Ed25519 public key, before its 32 raw bytes.
        x509 [0x30 0x2a 0x30 0x05 0x06 0x03 0x2b 0x65 0x70 0x03 0x21 0x00]
        public (.generatePublic (java.security.KeyFactory/getInstance "Ed25519")
                                (java.security.spec.X509EncodedKeySpec.
                                 (byte-array (concat x509 (decode public-key)))))
        verifier (java.security.Signature/getInstance "Ed25519")]
    (boolean
     (when signature
       (.initVerify verifier public)
       (.update verifier (.getBytes (str "legu-review-record\n" unsigned "}") "UTF-8"))
       (.verify verifier (decode signature))))))

(deftest a-mark-in-a-signed-store-is-signed-under-the-listed-name
  ;; The listed name is not git's, and git's is empty: in a signed store the
  ;; name comes from the signers list and git is never asked for one.
  (let [dir (scratch-repo!)
        key (list-key! dir "Listed Name")]
    (git! dir "config" "user.name" "")
    (is (= [0 ""] ((juxt :exit :err) (legu! dir "mark" "alpha.txt:2-4"))))
    (let [[header record & more] (sidecar-lines dir "alpha.txt")]
      (is (= "{\"schema\":4}" header))
      ;; Still one line per record, the signature last, after the hashes.
      (is (nil? more))
      (is (re-matches (alpha-2-4 "Listed Name" base64-64-bytes) record) record)
      (is (verifies? key record))
      (is (not (verifies? key (str/replace record "Listed Name" "Listed Namf")))))))

(deftest a-ticket-reference-in-a-signed-store-is-not-signed
  (let [dir (scratch-repo!)]
    (write-files! dir {".review/signers" listed-elsewhere})
    (is (= [0 ""] ((juxt :exit :err) (legu! dir "ticket" "alpha.txt:3" "T-1"))))
    (is (not (str/includes? (second (sidecar-lines dir "alpha.txt")) "signature")))))

(deftest a-mark-in-a-signed-store-refuses-what-it-cannot-sign
  (let [dir (scratch-repo!)
        mark ["mark" "alpha.txt:1-2"]]
    (write-files! dir {".review/signers" listed-elsewhere})
    (fails-with dir mark (str "no signing key at " (key-file dir "key.pub")
                              "; create one with legu key init"))
    (legu! dir "key" "init")
    (fails-with dir mark (str ".review/signers does not list the key in " (key-file dir "key.pub")
                              "; add it with legu key add"))
    (legu! dir "key" "add")
    ;; A record already in place is what a refused re-mark must leave alone.
    (is (zero? (:exit (apply legu! dir mark))))
    (fails-with dir (conj mark "--reviewer" reviewer)
                "a signed store takes the reviewer from .review/signers, so mark does not take --reviewer")
    (fs/delete (key-file dir "key"))
    (fails-with dir mark (str "no signing key at " (key-file dir "key")
                              "; create one with legu key init"))))

(deftest a-refused-mark-leaves-the-sidecar-as-it-was
  ;; The key is read and checked before mark prunes anything, so a re-mark
  ;; that would supersede a record and then cannot sign leaves it in place.
  (let [dir (scratch-repo!)
        other (scratch-repo!)
        remark ["mark" "alpha.txt:1-5"]]
    (legu! dir "key" "init")
    (legu! dir "key" "add")
    (is (zero? (:exit (legu! dir "mark" "alpha.txt:2-4"))))
    (let [before (sidecar-lines dir "alpha.txt")]
      (spit (key-file dir "key") "not a key\n")
      (let [{:keys [exit out err]} (apply legu! dir remark)]
        (is (= [1 ""] [exit out]))
        (is (str/starts-with? err (str "legu: cannot read the signing key at "
                                       (key-file dir "key") ": "))))
      (legu! other "key" "init")
      (fs/copy (key-file other "key") (key-file dir "key") {:replace-existing true})
      (fails-with dir remark (str "the signing key at " (key-file dir "key")
                                  " is not the private half of " (key-file dir "key.pub")))
      (is (= before (sidecar-lines dir "alpha.txt"))))))

(deftest a-mark-in-an-unsigned-store-reads-no-key-and-signs-nothing
  ;; A key that could not sign anything, and no signers list to call for one.
  (let [dir (scratch-repo!)]
    (legu! dir "key" "init")
    (spit (key-file dir "key") "not a key\n")
    (is (= [0 ""] ((juxt :exit :err) (legu! dir "mark" "alpha.txt:2-4"))))
    (let [[header record & more] (sidecar-lines dir "alpha.txt")]
      (is (= "{\"schema\":4}" header))
      (is (nil? more))
      (is (re-matches (alpha-2-4 reviewer nil) record) record))))

(deftest forget-and-supersede-leave-the-signatures-of-other-records-alone
  (let [dir (scratch-repo!)
        key (list-key! dir reviewer)
        _ (legu! dir "mark" "alpha.txt:1-2")
        _ (legu! dir "mark" "alpha.txt:4-5")
        [_ kept replaced] (sidecar-lines dir "alpha.txt")]
    (is (verifies? key kept))
    (is (verifies? key replaced))
    ;; A second mark of 4-5 supersedes that record and no other.
    (is (= 0 (:exit (legu! dir "mark" "alpha.txt:4-5"))))
    (let [[_ first-line second-line & more] (sidecar-lines dir "alpha.txt")]
      (is (= kept first-line))
      (is (verifies? key second-line))
      (is (nil? more)))
    (is (= 0 (:exit (legu! dir "forget" "alpha.txt:4-5"))))
    (is (= [kept] (rest (sidecar-lines dir "alpha.txt"))))))

;; ---------------------------------------------------------------- verify

;; ADR-0016: verify checks every review record's signature against the
;; signers list and exits 1 when any does not hold, so CI can gate on it. The
;; tampering is done by rewriting the scratch tree's files by hand.

(defn- verify! [dir & args]
  ((juxt :exit :out :err) (apply legu! dir "verify" args)))

(defn- strip-signature [line]
  (str/replace line #",\"signature\":\"[^\"]*\"" ""))

(deftest verify-in-an-unsigned-store-says-so-and-passes
  (let [dir (scratch-repo!)]
    (legu! dir "mark" "alpha.txt:2-4")
    (is (= [0 "the store is not signed: there is no .review/signers\n" ""]
           (verify! dir)))
    (is (= {:signed false :records [] :signers-errors []}
           (json/parse-string (:out (legu! dir "verify" "--json")) true)))))

(defn- rewrite! [file f]
  (spit file (f (slurp file))))

(defn- verify-json [dir & args]
  (let [{:keys [exit out]} (apply legu! dir "verify" "--json" args)]
    (assoc (json/parse-string out true) :exit exit)))

(defn- signed-store!
  "A signed scratch tree with alpha.txt:2-4 and all of sub/beta.txt marked
   under the listed name. Returns the tree."
  []
  (let [dir (scratch-repo!)]
    (list-key! dir reviewer)
    (legu! dir "mark" "alpha.txt:2-4")
    (legu! dir "mark" "sub/beta.txt")
    dir))

(defn- alpha-finding
  "What verify's human output says of the alpha.txt:2-4 record, then the
   count of a store holding it and beta's valid record."
  [outcome reason]
  (str ".review/sidecars/alpha.txt.jsonl  alpha.txt:2-4  " reviewer "  " outcome "  (" reason ")\n"
       "2 review records, 1 not valid\n"))

(defn- outcomes [dir]
  (mapv (juxt :path :outcome) (:records (verify-json dir))))

(deftest verify-passes-a-store-whose-records-all-hold
  (let [dir (signed-store!)]
    (is (= [0 "2 review records, all valid\n" ""]
           (verify! dir)))
    (is (= {:exit 0
            :signed true
            :records [{:file ".review/sidecars/alpha.txt.jsonl" :path "alpha.txt" :start 2 :end 4
                       :reviewer reviewer :outcome "valid" :reason nil}
                      {:file ".review/sidecars/sub/beta.txt.jsonl" :path "sub/beta.txt" :start 1 :end 3
                       :reviewer reviewer :outcome "valid" :reason nil}]
            :signers-errors []}
           (verify-json dir)))))

(deftest verify-reports-a-hash-edited-under-a-valid-signature
  (let [dir (signed-store!)]
    (rewrite! (sidecar-file dir "alpha.txt")
              #(str/replace % (sha256 (get fixture "alpha.txt")) (sha256 "edited")))
    (is (= [1 (alpha-finding "bad-signature" (str "no key listed for " reviewer " made this signature")) ""]
           (verify! dir)))
    (is (= [["alpha.txt" "bad-signature"] ["sub/beta.txt" "valid"]] (outcomes dir)))
    (is (= 1 (:exit (verify-json dir))))))

(deftest verify-reports-a-signature-that-is-not-one-without-crashing
  (let [dir (signed-store!)
        f (sidecar-file dir "alpha.txt")
        signature #"\"signature\":\"[^\"]*\""]
    (doseq [replacement ["\"signature\":\"not base64!\"" "\"signature\":\"AAAA\"" "\"signature\":7"]]
      (rewrite! f #(str/replace-first % signature replacement))
      (is (= [1 (alpha-finding "bad-signature" "the signature is not 64 bytes of base64") ""]
             (verify! dir))
          replacement)
      (rewrite! f #(str/replace-first % #"\"signature\":(\"[^\"]*\"|7)" "\"signature\":\"\"")))))

(defn- hand-written-alpha!
  "Replaces alpha.txt's sidecar with one review record of 2-4 under the JSON
   `reviewer`, carrying a well-formed signature no key made."
  [dir reviewer-json]
  (write-sidecar! dir "alpha.txt"
                  (str "{\"schema\":4}\n"
                       "{\"start\":2,\"end\":4,\"reviewer\":" reviewer-json ","
                       "\"timestamp\":\"2020-01-01T00:00:00Z\",\"commit\":\"" (apply str (repeat 40 "0")) "\","
                       "\"file-hash\":\"" (sha256 (get fixture "alpha.txt")) "\","
                       "\"content-hash\":\"" (sha256 "two\nthree\nfour") "\","
                       "\"signature\":\"" (apply str (repeat 86 "A")) "==\"}\n")))

(deftest verify-reports-a-record-whose-reviewer-has-no-listed-key
  (let [dir (signed-store!)]
    (hand-written-alpha! dir "\"Nobody\"")
    (is (= [1 (str ".review/sidecars/alpha.txt.jsonl  alpha.txt:2-4  Nobody  unlisted-signer"
                   "  (.review/signers lists no key for Nobody)\n"
                   "2 review records, 1 not valid\n")
            ""]
           (verify! dir)))
    (is (= [["alpha.txt" "unlisted-signer"] ["sub/beta.txt" "valid"]] (outcomes dir)))
    ;; A null reviewer is the name no binding has, not a match for the
    ;; missing signer's.
    (hand-written-alpha! dir "null")
    (is (= [1 (str ".review/sidecars/alpha.txt.jsonl  alpha.txt:2-4  null  unlisted-signer"
                   "  (.review/signers lists no key for null)\n"
                   "2 review records, 1 not valid\n")
            ""]
           (verify! dir)))))

(deftest verify-reports-a-name-the-signers-list-does-not-give-the-key
  (let [dir (signed-store!)]
    (write-files! dir {".review/signers" (str (public-key dir) " Someone Else\n")})
    (is (= [1 (str ".review/sidecars/alpha.txt.jsonl  alpha.txt:2-4  " reviewer "  name-mismatch"
                   "  (signed by the key .review/signers lists for Someone Else)\n"
                   ".review/sidecars/sub/beta.txt.jsonl  sub/beta.txt:1-3  " reviewer "  name-mismatch"
                   "  (signed by the key .review/signers lists for Someone Else)\n"
                   "2 review records, 2 not valid\n")
            ""]
           (verify! dir)))
    (is (= [["alpha.txt" "name-mismatch"] ["sub/beta.txt" "name-mismatch"]] (outcomes dir)))))

(deftest verify-reports-a-record-with-its-signature-removed
  (let [dir (signed-store!)]
    (rewrite! (sidecar-file dir "alpha.txt") strip-signature)
    (is (= [1 (alpha-finding "unsigned" "no signature in a signed store") ""]
           (verify! dir)))
    (is (= [["alpha.txt" "unsigned"] ["sub/beta.txt" "valid"]] (outcomes dir)))))

(deftest verify-reports-each-signers-line-that-does-not-parse-once
  (let [dir (signed-store!)
        key (public-key dir)]
    (write-files! dir {".review/signers" (str "# trusted\n\n" key " " reviewer "\n"
                                              "onlyonefield\n"
                                              "AAAA Short Key\n")})
    (is (= [1 (str ".review/signers:4  onlyonefield  (not a public key, one space, then a name)\n"
                   ".review/signers:5  AAAA Short Key  (not a 32-byte Ed25519 public key in base64)\n"
                   "2 review records, all valid; 2 lines of .review/signers do not parse\n")
            ""]
           (verify! dir)))
    (is (= {:exit 1
            :signers-errors [{:line 4 :text "onlyonefield"
                              :reason "not a public key, one space, then a name"}
                             {:line 5 :text "AAAA Short Key"
                              :reason "not a 32-byte Ed25519 public key in base64"}]}
           (select-keys (verify-json dir) [:exit :signers-errors])))
    (is (= [["alpha.txt" "valid"] ["sub/beta.txt" "valid"]] (outcomes dir)))))

(deftest verify-scopes-to-a-file-or-a-directory
  (let [dir (signed-store!)]
    (rewrite! (sidecar-file dir "alpha.txt") strip-signature)
    (doseq [path ["sub" "sub/" "sub/beta.txt"]]
      (is (= [0 "1 review record, all valid\n" ""]
             (verify! dir path))
          path))
    (is (= [["alpha.txt" "unsigned"]] (mapv (juxt :path :outcome) (:records (verify-json dir "alpha.txt")))))
    (is (= [1 (str ".review/sidecars/alpha.txt.jsonl  alpha.txt:2-4  " reviewer "  unsigned"
                   "  (no signature in a signed store)\n"
                   "1 review record, 1 not valid\n")
            ""]
           (verify! dir "alpha.txt")))))

(deftest verify-fails-on-a-sidecar-it-cannot-read-under-its-path
  (let [dir (signed-store!)
        f (sidecar-file dir "sub/beta.txt")]
    (rewrite! f #(str % "<<<<<<< HEAD\n"))
    (let [{:keys [exit out err]} (legu! dir "verify")]
      (is (= [1 "1 review record, all valid; 1 sidecar could not be read\n"] [exit out]))
      (is (str/starts-with? err (str "legu: cannot read " f ": ")) err))
    (is (= [{:file ".review/sidecars/sub/beta.txt.jsonl"}]
           (mapv #(select-keys % [:file]) (:errors (verify-json dir)))))
    (is (= [0 "1 review record, all valid\n" ""]
           (verify! dir "alpha.txt")))))

(deftest verify-needs-no-local-key
  (let [dir (signed-store!)]
    (fs/delete-tree (fs/file (config-home dir) "legu"))
    (is (= [0 "2 review records, all valid\n" ""]
           (verify! dir)))))

(deftest verify-reports-a-key-listed-twice
  ;; One key binds to one reviewer, so a second line for it binds nothing and
  ;; is reported, whatever name it gives.
  (let [dir (scratch-repo!)]
    (legu! dir "key" "init")
    (legu! dir "key" "add")
    (legu! dir "mark" "alpha.txt:1-2")
    (spit (fs/file dir ".review" "signers") (str (public-key dir) " Someone Else\n")
          :append true)
    (is (= 1 (first (verify! dir))))
    (is (= [{:line 2 :text (str (public-key dir) " Someone Else")
             :reason "the key is already listed on line 1"}]
           (:signers-errors (verify-json dir))))
    (is (= [["alpha.txt" "valid"]] (outcomes dir)))))

(deftest verify-knows-two-keys-under-one-name-and-not-an-unlisted-one
  ;; A reviewer on two machines lists both keys under one name. Unlist the
  ;; second and its records can no longer be told from tampering.
  (let [dir (scratch-repo!)
        other (scratch-repo!)
        starts #(mapv (juxt :start :outcome) (:records (verify-json dir)))]
    (legu! dir "key" "init")
    (legu! dir "key" "add")
    (let [first-key (public-key dir)]
      (legu! dir "mark" "alpha.txt:1-2")
      (legu! other "key" "init")
      (doseq [name ["key" "key.pub"]]
        (fs/copy (key-file other name) (key-file dir name) {:replace-existing true}))
      (legu! dir "key" "add")
      (legu! dir "mark" "alpha.txt:4-5")
      (is (= [0 ""] ((juxt first last) (verify! dir))))
      (is (= [[1 "valid"] [4 "valid"]] (starts)))
      (spit (fs/file dir ".review" "signers") (str first-key " " reviewer "\n"))
      (is (= 1 (first (verify! dir))))
      (is (= [[1 "valid"] [4 "bad-signature"]] (starts)))
      (is (= "no key listed for Test Reviewer made this signature"
             (:reason (second (:records (verify-json dir)))))))))

(deftest an-unreadable-signers-list-is-an-error-not-a-crash
  (let [dir (scratch-repo!)]
    (legu! dir "key" "init")
    (fs/create-dirs (fs/file dir ".review" "signers"))
    (doseq [args [["verify"] ["mark" "alpha.txt:1-2"]]]
      (let [{:keys [exit out err]} (apply legu! dir args)]
        (is (= [1 ""] [exit out]))
        (is (str/starts-with? err "legu: cannot read .review/signers: "))))))

(deftest reading-commands-still-count-a-record-verify-rejects
  ;; A flipped signature character leaves every hash the anchoring reads as
  ;; it was, so only verify can tell.
  (let [dir (signed-store!)
        before [(coverage-json dir) (regions-json dir "alpha.txt") (:out (legu! dir "status"))]]
    (rewrite! (sidecar-file dir "alpha.txt")
              #(str/replace % #"\"signature\":\"(.)"
                            (fn [[_ c]] (str "\"signature\":\"" (if (= "A" c) "B" "A")))))
    (is (= [["alpha.txt" "bad-signature"] ["sub/beta.txt" "valid"]] (outcomes dir)))
    (is (= 6 (:reviewed (coverage-json dir))))
    (is (= before [(coverage-json dir) (regions-json dir "alpha.txt") (:out (legu! dir "status"))]))
    (rewrite! (sidecar-file dir "alpha.txt") strip-signature)
    (is (= [["alpha.txt" "unsigned"] ["sub/beta.txt" "valid"]] (outcomes dir)))
    (is (= before [(coverage-json dir) (regions-json dir "alpha.txt") (:out (legu! dir "status"))]))))

;; ---------------------------------------------------------------- completion

;; babashka.cli derives these from the same table that parses a command line,
;; so what is worth checking is not that a snippet exists but that what it
;; offers is what legu accepts. The shells below run the snippet for real; the
;; cases before them read the callback the snippet calls.

(def ^:private shells ["bash" "zsh" "fish" "powershell" "nushell"])

;; What every drive of completion is checked against, in one place: six copies
;; of these lists meant six edits to add a command.
(def ^:private offered-commands
  ["mark" "ticket" "forget" "status" "regions" "stale" "next" "coverage" "key" "verify"])

(def ^:private offered-subcommands {"key" ["init" "show" "add"]})

;; Keyed by the words before the options, so a subcommand fits beside a command.
(def ^:private offered-options
  {["next"] ["--limit" "--order" "--help" "--json" "--version"]
   ["status"] ["--gaps" "--help" "--json" "--version"]
   ["mark"] ["--reviewer" "--help" "--json" "--version"]
   ["key" "init"] ["--help" "--json" "--version"]
   ["verify"] ["--help" "--json" "--version"]})

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
    (is (= offered-commands (candidates dir "")))
    (doseq [[group subcommands] offered-subcommands]
      (is (= subcommands (candidates dir group "")) group))))

(deftest completion-offers-only-the-options-the-command-takes
  (let [dir (scratch-repo!)]
    (doseq [[command expected] offered-options]
      (is (= expected (apply candidates dir (conj command "--"))) command))
    ;; The claim under all of them: nothing offered is anything the command
    ;; would turn down. An option legu has elsewhere is refused by name, so a
    ;; wrong candidate shows up here as that refusal rather than as a missing
    ;; flag.
    (doseq [command (keys offered-options)
            candidate (apply candidates dir (conj command "--"))
            :let [{:keys [err]} (apply legu! dir (conj command candidate "x"))]]
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
   "HOME" dir
   "XDG_CONFIG_HOME" (config-home dir)})

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
        (doseq [[group subcommands] offered-subcommands]
          (is (= subcommands (offered group "")) group))
        (doseq [[command expected] offered-options]
          (is (= expected (apply offered (conj command "--"))) command))
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
        (is (= offered-commands (offered "legu ")))
        (doseq [[group subcommands] offered-subcommands]
          (is (= subcommands (offered (str "legu " group " "))) group))
        (doseq [[command expected] offered-options]
          (is (= expected (offered (str "legu " (str/join " " command) " --"))) command))
        (is (= offered-orders (offered "legu next --order ")))))))

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
        (doseq [[group subcommands] offered-subcommands
                :let [painted (offered (str "legu " group " "))]
                subcommand subcommands]
          (is (str/includes? painted subcommand) (str group " " subcommand)))
        (doseq [[command expected] offered-options
                :let [painted (offered (str "legu " (str/join " " command) " --"))]]
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
  ;; for byte. The literal is the layout ADR-0015 fixes, with the signature
  ;; lgu-01m28srsmekn added as the last key and the last tie-breaker: c and d
  ;; differ in nothing else.
  (let [render #'legu.main/render-sidecar
        a {:start 10 :end 20 :reviewer "a \"quoted\" name" :timestamp "2026-08-28T10:00:28Z"
           :commit "c439a988" :file-hash "be9c" :content-hash "d65c" :signature "c2lnbmVk"}
        c {:start 30 :end 31 :reviewer "c" :timestamp "2026-08-28T10:00:28Z"
           :commit "c439a988" :file-hash "be9c" :content-hash "1111" :signature "BBBB"}
        d (assoc c :signature "AAAA")
        b {:start 1 :end 5 :reviewer "b" :timestamp "2026-08-28T10:00:28Z"
           :commit "c439a988" :file-hash "be9c" :content-hash "0000"}
        ;; An opaque record made from a region still carries nil bounds.
        o {:opaque true :start nil :end nil :content-hash nil
           :ticket "lgu-01k7" :timestamp "2026-08-28T10:00:29Z" :commit "c439a988" :file-hash "be9c"}
        t {:start 1 :end 1 :ticket "T-1" :timestamp "2026-08-28T10:00:29Z"
           :commit "c439a988" :file-hash "be9c" :content-hash "0000"}
        expected (str "{\"schema\":4}\n"
                      "{\"start\":1,\"end\":5,\"reviewer\":\"b\",\"timestamp\":\"2026-08-28T10:00:28Z\",\"commit\":\"c439a988\",\"file-hash\":\"be9c\",\"content-hash\":\"0000\"}\n"
                      "{\"start\":10,\"end\":20,\"reviewer\":\"a \\\"quoted\\\" name\",\"timestamp\":\"2026-08-28T10:00:28Z\",\"commit\":\"c439a988\",\"file-hash\":\"be9c\",\"content-hash\":\"d65c\",\"signature\":\"c2lnbmVk\"}\n"
                      "{\"start\":30,\"end\":31,\"reviewer\":\"c\",\"timestamp\":\"2026-08-28T10:00:28Z\",\"commit\":\"c439a988\",\"file-hash\":\"be9c\",\"content-hash\":\"1111\",\"signature\":\"AAAA\"}\n"
                      "{\"start\":30,\"end\":31,\"reviewer\":\"c\",\"timestamp\":\"2026-08-28T10:00:28Z\",\"commit\":\"c439a988\",\"file-hash\":\"be9c\",\"content-hash\":\"1111\",\"signature\":\"BBBB\"}\n"
                      "{\"opaque\":true,\"ticket\":\"lgu-01k7\",\"timestamp\":\"2026-08-28T10:00:29Z\",\"commit\":\"c439a988\",\"file-hash\":\"be9c\"}\n"
                      "{\"start\":1,\"end\":1,\"ticket\":\"T-1\",\"timestamp\":\"2026-08-28T10:00:29Z\",\"commit\":\"c439a988\",\"file-hash\":\"be9c\",\"content-hash\":\"0000\"}\n")]
    (is (= expected (render {:regions [a b c d] :tickets [o t]})))
    (is (= expected (render {:regions [c d b a] :tickets [t o]})))))

(let [{:keys [fail error]} (try (run-tests) (finally (run! fs/delete-tree @scratch-dirs)))]
  (System/exit (if (pos? (+ fail error)) 1 0)))
