---
id: lgu-01m238vjgnh6
title: Move legu's CLI onto babashka.cli
status: closed
type: epic
priority: 2
mode: hitl
created: '2026-09-09T14:23:54.389589203Z'
updated: '2026-09-09T16:26:32.269153207Z'
closed: '2026-09-09T16:26:32.269153207Z'
---

## Description

legu hand-rolls its whole command line: a `usage` string, a `flags` table, a `commands` table carrying per-command
argument counts, and a parse loop, all in the `cli` section of the script. Three of those four drift independently —
adding an option means editing the flags table and the usage string, and nothing checks that they agree. Per-command
option scoping does not exist, so `legu status --limit 3` is accepted and silently ignored.

`babashka.cli` ships inside babashka, so adopting it adds no dependency and keeps the "babashka and git, nothing else"
promise intact. It replaces all four structures with one dispatch tree that generates its own help, and it brings
shell completions, which legu has no way to offer today.

Every feature this epic uses was verified against babashka 1.13.220 (babashka.cli 0.12.89): dispatch auto-help,
`:positional` with `:args->opts`, `:restrict-args`, `:enum`, `:inherit`, `:error-fn`, and the completions command.
Parity with today's parser was checked too, and holds: the `--` terminator, `--json=false`, `--no-json`, options before
the command, and a bare `legu` or `legu --version` reaching a root `{:cmds []}` entry.

The constraint that shapes the sequencing: these are babashka.cli 0.12.7x-0.12.8x features, so they raise legu's
minimum babashka. That bump lands first, on its own.

## Notes

**2026-09-09T15:02:21.045144278Z**

Four facts in this epic were checked against bb 1.13.220 during planning and did not hold.

--no-json is an unknown-option error today, not accepted input; babashka.cli adds the spelling rather than preserving it. AC amended on lgu-01m238wawfq7.

Shell completions shipped in babashka.cli 0.11.70, not 0.12.70, and bb 1.13.219 bundles 0.12.85, not 0.12.88. The floor conclusion survives: 1.13.219 is still the earliest release carrying every feature named. 1.13.220 is the recommended floor anyway, because Inherited options: in generated help and format-command-help accepting :spec both arrived in 0.12.86, and both are load-bearing for the help this epic promises.

The -- terminator does not survive :args->opts. (cli/parse-opts ["--" "-weird.txt"] {:args->opts [:path]}) returns {} — post-terminator tokens land in :args and never fill a positional, so :restrict-args rejects them. legu status -- -weird.txt works today and still works after the dispatch move, but breaks in lgu-01m238wskh6s unless the command also reads trailing :args. That is AC 6 of that ticket, asserted there as unaffected.

Dispatch does not reproduce two behaviors for free. A bare legu does not auto-print help (auto-help fires only on --help), and legu badcmd / legu --badopt fall into the root {:cmds []} entry and exit 0 unless it carries :restrict true :restrict-args true — and then the messages are the library's, not legu's.

Also: the clj-kondo baseline is not clean. legu:5 (namespace name) and legu:85 (redundant nested str), exit 3. That is the bar to hold, not zero.

**2026-09-09T16:26:32.269153207Z**

legu's command line is one babashka.cli dispatch tree. The usage string, the flags table, the parse loop and the per-command argument counts are gone; options and arguments are declared once and help, errors and completions are generated from that declaration. The four structures that drifted independently are one.

What the epic promised and got: per-command option scoping, so `legu status --limit 3` is an error naming the option instead of silently ignored; positional arguments in the spec, replacing five hand-written guards; generated help for the root and every command; and shell completions for bash, zsh and fish, which legu had no way to offer before. No new dependency — babashka.cli ships inside babashka.

Landed in five phases, one commit each. The floor and the seam (7df3719), the rewrite (98cd09f), the tightening (c9c46e7), completions (d910ab8).

A ticket was added to the epic at planning time and closed with it: lgu-01m23a8m1t5c, a black-box CLI suite. legu's only tests were the Emacs ERT ones, which need an emacs (there is none in this environment) and cover only what the package calls, so "behavior unchanged" — the premise the whole move rested on — had nothing checking it. The suite recorded the old parser case by case before anything moved, and every later phase ran it. It ends at 36 tests and 227 assertions, and it earned its place: it caught that dispatch stops reading options at the first unclaimed positional, which the planning prototype had missed because standalone parse-args does not behave that way.

Four claims in this epic's own text were checked during planning and did not hold. --no-json was an unknown option, not accepted input, so the move added the spelling rather than preserving it. Completions shipped in babashka.cli 0.11.70 and bb 1.13.219 bundles 0.12.85, not the numbers named here; the floor conclusion survived, and 1.13.220 was chosen because the help this epic promises needs 0.12.86. The -- terminator does not survive :args->opts, contrary to the claim it was unaffected. And dispatch reproduces neither a bare `legu` printing help nor legu's own unknown-command wording without being asked.

Every phase was reviewed on two axes before its commit, and the reviews found what the implementations and their own test runs did not: an argument key exposed as a hidden option that took an unvalidated value and silently dropped a real argument; a terminator implementation that bypassed the spec and wrote a blank-id review record; an unknown-option message that named an option the reader had typed correctly; a --help=true that errored instead of printing help; a README line for fish that failed as written; and three ways the completion tests could report green without checking anything. All fixed before the commit that carried them.

Left open, parented off this epic: lgu-01m23d9faenk. `mark`'s help says a region is reviewed at HEAD, which ADR-0006 contradicts, and `coverage`'s says never-read, which CONTEXT.md avoids. Both were carried verbatim from the old usage blob; rewording user-facing text under a no-behavior-change ticket was the wrong place, and the coverage half may imply a breaking JSON-key change for the Emacs package.

Not verified anywhere in this run: the Emacs ERT suite, for want of an emacs. Every command line emacs/legu.el builds was run by hand instead, and the six sites that surface legu's stderr verbatim were checked by inspection; die is unchanged, so their shape is.
