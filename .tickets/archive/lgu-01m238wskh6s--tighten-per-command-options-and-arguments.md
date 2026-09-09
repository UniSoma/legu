---
id: lgu-01m238wskh6s
title: Tighten per-command options and arguments
status: closed
type: task
priority: 2
mode: afk
created: '2026-09-09T14:24:34.417431312Z'
updated: '2026-09-09T16:03:30.373457728Z'
closed: '2026-09-09T16:03:30.373457728Z'
parent: lgu-01m238vjgnh6
acceptance:
- title: Each option is declared only on the commands that read it; an option passed to a command that ignores it is an error naming the option
  done: true
- title: Positional arguments are declared in the spec, replacing the per-command argument counts and the hand-written missing-argument guards
  done: true
- title: Help renders an Arguments section distinguishing required <path> from optional [<path>]
  done: true
- title: --order is an ordered enum whose values stay strings, and help and errors list dir before cochange
  done: true
- title: --limit coerces to a long and rejects zero, negatives and non-numbers, including --limit -3
  done: true
- title: A path containing a colon still parses as path:start-end, and a path starting with a hyphen still works after --
  done: true
- title: The close summary records whether missing-argument wording matches today's messages or the library's
  done: true
- title: The README documents that options are now scoped per command, since this rejects input that used to be accepted
  done: true
deps:
- lgu-01m238wawfq7
---

## Description

The tightening the dispatch move deliberately held back. This is the only behavior change in the epic, which is why it
is its own ticket: it can be reverted without giving up the parser refactor underneath it.

Scope each option to the commands that actually read it. Today every option is global, so `legu status --limit 3` is
accepted and silently ignored — the user gets no signal that the flag did nothing. After this, it is an error.

Replace the `commands` table's per-command argument counts and the hand-written guards ("mark needs a path", "ticket
needs a ticket id", "forget needs a path") with `:positional` entries plus `:args->opts` and `:restrict-args`. Help then
grows an Arguments section rendering required arguments as `<path>` and optional ones as `[<path>]`, generated from the
same spec that enforces them. Note that babashka.cli's missing-argument wording differs from legu's current messages;
decide whether to match today's text through `:error-fn` or accept the library's, and say which in the close summary.

`--order` becomes `:enum ["dir" "cochange"]` rather than the current set. The values stay strings, so the comparison in
the next command is untouched; the gain is ordering — an enum preserves declaration order in help, errors and
completions, where a set sorts alphabetically and would print cochange before dir.

`--limit` becomes `:coerce :long` with `:validate pos?`, replacing the hand-rolled parse-long and positivity check.
`--limit -3` was verified to error rather than being read as an option.

Paths can contain a colon (legu takes `path:start-end`) and the `--` terminator still handles a path beginning with a
hyphen; neither is affected by marking these arguments positional.

## Notes

**2026-09-09T16:03:30.373457728Z**

Options are scoped: the dispatch level keeps only --json, --version and --help, command-options holds --reviewer, --limit, --order and --gaps, and each command names the keys it reads. Every command entry carries :restrict, so `legu status --limit 3` is `status does not take --limit` where it used to be accepted and ignored. refused-option distinguishes three cases — an option on the wrong command, an option before the command that owns it (`--gaps belongs to status, and stands after it`), and one legu has nowhere (`unknown option: --badopt`).

Arguments are declared :positional with a :ref, and the five hand-written guards (mark/ticket/forget/regions needs a path, ticket needs a ticket id) and the per-command argument count are gone. Commands read (:target opts), (:id opts), (:path opts).

Criterion 7, the recorded decision: **the library's words, in legu's voice.** The surplus-argument message cannot be reconstructed from the library's data — :restrict-args names the surplus token, not a count — so matching today's `mark takes 1 argument, got 2` was not available, and keeping legu's wording for absence while the library worded surplus is the half-and-half worth avoiding. So both come from the spec that declares the arguments and name them in the same <target> / [<path>] the help prints. They are lowercase, because every other message legu writes is, and legu writes these itself.

The terminator was the hard part, as the epic note warned. The first implementation split argv at the first `--` before dispatch and merged the tail back after parsing, and review found three defects in it: `legu -- status` lost the command name; `legu ticket -- alpha.txt ""` bypassed the spec's own :validate and wrote a blank-id review record; and `legu ticket -- alpha.txt` named <target>, which had been supplied, instead of <id>. All three came from the same cause — a second parser beside the library's, re-injecting values the spec never saw.

Reworked: no :require and no :restrict-args on a command entry, and split-terminator deleted. Post-terminator tokens reach :args on their own, and dispatch-entry fills the unfilled positionals from them, counts the surplus, and applies the spec's :validate, in one place. missing-argument names the first argument the command declares, is not content to run without, and did not get. refused-value words a turned-down value once, so the parser's path and the terminator's path cannot drift.

Review also found that a hand-rolled scan for --help/-h/--version in argv missed the = form, so `legu mark --help=true` answered `Required argument: <target>` instead of printing help. Dropping :require removed the need for that scan entirely; both --help=true and --version=true now print.

Three consequences of scoping, each documented in the README and pinned by the suite: a scoped option cannot precede its command; root help lists only legu's own three options, each command's page listing its own; and --json, --version and --help stay inherited everywhere.

Suite: 29 tests, 127 assertions, green. Linter at its two-finding baseline.
