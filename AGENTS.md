# legu

- `bb test` runs the CLI suite and ERT; `bb lint` runs clj-kondo and the prose
  width check. A change is done when both pass.
- Reviews check [CODING_STANDARDS.md](CODING_STANDARDS.md). The vocabulary is
  in [CONTEXT.md](CONTEXT.md), the decisions in [docs/adr/](docs/adr/).
- `legu` is one babashka script with no `.clj` extension. Outline it with
  `grep -n '^;; ----\|^(def' legu`; read one form with
  `clj-surgeon :op :cat :file legu :form NAME`.
- Running `legu` by hand: set `XDG_CONFIG_HOME` and `HOME` to a scratch
  directory, so it never reads or writes the real `~/.config/legu`.
