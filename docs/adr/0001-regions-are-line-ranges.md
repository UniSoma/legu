# Regions are line ranges; legu knows no language

legu tracks review state for codebases that mix Clojure, YAML, shell and SQL,
and the same tool has to work on all of them. A region is `(path, start, end)`
and nothing else: no parsers, no syntactic units, no per-language plugins,
ever. An editor front end may use *its* knowledge of the language to pick a
region (`C-M-h C-c r r` marks a defun in Emacs); legu itself never does. The
cost is that regions do not follow refactors that a parser would understand;
the benefit is that one anchoring algorithm covers every file in the tree.
