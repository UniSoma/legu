---
id: lgu-01m238wawfq7
title: Move argument parsing onto cli/dispatch, behavior unchanged
status: closed
type: task
priority: 2
mode: afk
created: '2026-09-09T14:24:19.343421336Z'
updated: '2026-09-09T15:41:44.545131119Z'
closed: '2026-09-09T15:41:44.545131119Z'
parent: lgu-01m238vjgnh6
acceptance:
- title: The usage string, flags table, commands table and parse-args loop are gone, replaced by one dispatch tree
  done: true
- title: legu --help and legu <command> --help both render from the spec, and every command carries a :doc line
  done: true
- title: 'Errors still print as "legu: <msg>" on stderr with exit 1, via :error-fn'
  done: true
- title: --json parses both before and after the command, declared once as an inherited option
  done: true
- title: A bare legu prints help and exits 0; legu --version prints what it prints today, in both human and --json form
  done: true
- title: Every option legu accepts today is still accepted in the same position with the same effect; no option becomes an error in this ticket
  done: true
- title: The -- terminator and --json=false behave as they do today; --no-json, which is an unknown-option error today, becomes accepted as {:json false} and the close summary records that as a deliberate addition
  done: true
- title: The Emacs test suite passes without changes to the tests, or the close summary records that no emacs was available and names the six emacs/legu.el sites that surface legu's stderr verbatim as checked by inspection instead
  done: true
deps:
- lgu-01m238vy775q
- lgu-01m23a8m1t5c
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

## Notes

**2026-09-09T15:41:44.545131119Z**

The usage blob, the flags table, parse-args and the commands table are gone. One dispatch tree: `options` declares every option once at the dispatch level, `commands` is data with a :doc per command, and -main calls cli/dispatch. find-root and the binding of *root*/*git?* are unchanged, and every cmd-* still receives {:args … :opts …}, so nothing below the cli section moved.

The planning prototype missed one thing the suite caught: babashka.cli's dispatch stops reading options at the first argument no key claims, so `legu mark <target> --reviewer NAME` arrived as three arguments and no options. Standalone cli/parse-args does not behave that way, which is why it was not predicted. Each command entry therefore declares :args->opts, and the bound values go straight back to the front of :args. Reading them from opts, and requiring them there, is lgu-01m238wskh6s.

Review caught that the first version of that fix declared the argument keys as hidden {:no-doc true} options. That made --target, --path and --id accepted spellings legu never had; `mark --target` with no value coerced to true and reached parse-target as a raw ClassCastException, and `mark --target a b` silently dropped an argument without the arity error. Declaring them :positional instead fixes all three — babashka.cli refuses a positional key as a flag — and as a side effect restores the argument shapes to help, which the old blob showed and :no-doc had hidden. `legu mark --help` now prints an Arguments section. Two suite cases pin it.

Also from review: the unknown-option message searched argv for any dash token containing the flag's letters, so `legu status --json -js` reported `unknown option: --json`, naming an option the reader typed correctly. It now matches on the token that starts with the flag. Pinned by a case.

--order's error message reads its values back out of the spec rather than repeating them; two lists that had to agree by hand is the drift this move set out to end. --limit and --reviewer keep their own wording through option-message, because babashka.cli reports a missing value before it coerces one, so `legu next --limit` cannot get its message from :validate.

The per-command argument count stays hand-written with its exact message, and no option is scoped to a command yet: `legu status --limit 3` is still accepted and ignored. Both belong to lgu-01m238wskh6s.

--no-json is the one deliberate change, per criterion 8: an unknown option before, {:json false} now. Its suite case was rewritten from an error recording to an acceptance and says so.

Criterion 7's escape hatch was taken: there is no emacs on this machine, so emacs/legu-tests.el was not run. Checked by inspection and by running every command line the package builds — legu.el:599 (--version --json), :679-680 (status/stale --json), :1026 and :1620 (regions <path> --json), :1405-1406 (mark <target> --reviewer <name>), :1462 (ticket), :1485 (forget) and the :1802 retry — all still parse and answer as before. The six sites that surface legu's stderr verbatim (:1411-1412, :1421-1422, :1468-1469, :1494-1495, :1630, :1809) all receive text from die, which is untouched.

Two help strings kept wording that disagrees with CONTEXT.md and ADR-0006; rewording user-facing text under a no-behavior-change ticket was the wrong place, so lgu-01m23d9faenk carries them.

Suite: 27 tests, 105 assertions, green. Linter at its two-finding baseline.
