---
id: lgu-01m238wskh6s
title: Tighten per-command options and arguments
status: open
type: task
priority: 2
mode: afk
created: '2026-09-09T14:24:34.417431312Z'
updated: '2026-09-09T14:24:59.862513809Z'
parent: lgu-01m238vjgnh6
acceptance:
- title: Each option is declared only on the commands that read it; an option passed to a command that ignores it is an error naming the option
  done: false
- title: Positional arguments are declared in the spec, replacing the per-command argument counts and the hand-written missing-argument guards
  done: false
- title: Help renders an Arguments section distinguishing required <path> from optional [<path>]
  done: false
- title: --order is an ordered enum whose values stay strings, and help and errors list dir before cochange
  done: false
- title: --limit coerces to a long and rejects zero, negatives and non-numbers, including --limit -3
  done: false
- title: A path containing a colon still parses as path:start-end, and a path starting with a hyphen still works after --
  done: false
- title: The close summary records whether missing-argument wording matches today's messages or the library's
  done: false
- title: The README documents that options are now scoped per command, since this rejects input that used to be accepted
  done: false
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
