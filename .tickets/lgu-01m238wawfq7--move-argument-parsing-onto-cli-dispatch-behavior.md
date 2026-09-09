---
id: lgu-01m238wawfq7
title: Move argument parsing onto cli/dispatch, behavior unchanged
status: open
type: task
priority: 2
mode: afk
created: '2026-09-09T14:24:19.343421336Z'
updated: '2026-09-09T14:24:59.757389052Z'
parent: lgu-01m238vjgnh6
acceptance:
- title: The usage string, flags table, commands table and parse-args loop are gone, replaced by one dispatch tree
  done: false
- title: legu --help and legu <command> --help both render from the spec, and every command carries a :doc line
  done: false
- title: 'Errors still print as "legu: <msg>" on stderr with exit 1, via :error-fn'
  done: false
- title: --json parses both before and after the command, declared once as an inherited option
  done: false
- title: A bare legu prints help and exits 0; legu --version prints what it prints today, in both human and --json form
  done: false
- title: The -- terminator, --json=false and --no-json behave as they do today
  done: false
- title: Every option legu accepts today is still accepted in the same position with the same effect; no option becomes an error in this ticket
  done: false
- title: The Emacs test suite passes without changes to the tests
  done: false
deps:
- lgu-01m238vy775q
---

## Description

Replace the four hand-maintained structures in legu's `cli` section — the `usage` string, the `flags` table, the
`commands` table, and the `parse-args` loop — with a single `babashka.cli` dispatch tree. Help is then generated from
the same data the parser reads, so the two cannot disagree. `legu mark --help` starts printing mark's own arguments and
options; today it prints the whole global usage blob.

This ticket is a pure refactor. Every option legu accepts today it still accepts, in the same positions, with the same
effect. The tightening that dispatch makes possible — rejecting options that do not belong to a command, declaring
positional arguments — is deliberately held back so that it can be reverted on its own.

Two things have to survive intact, because the Emacs package depends on them:

- `emacs/legu.el` surfaces legu's stderr to the user verbatim in five places. dispatch's default error output is
  `Error: <msg>` plus a usage hint; legu's `die` prints `legu: <msg>` and exits 1. An `:error-fn` restores that.
- The package sends `--json` after the command in most calls but before it for the version handshake. Both parse when
  `--json` is declared `:inherit true` at the dispatch level; this was verified.

A root `{:cmds [] :fn ...}` entry catches a bare `legu` and `legu --version`, which today are handled by the cond in
`-main`. Bare `legu` prints help and exits 0, as it does now.

The `--` terminator, `--json=false` and `--no-json` were all verified to behave as they do today.
