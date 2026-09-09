---
id: lgu-01m238vjgnh6
title: Move legu's CLI onto babashka.cli
status: open
type: epic
priority: 2
mode: hitl
created: '2026-09-09T14:23:54.389589203Z'
updated: '2026-09-09T15:02:21.045144278Z'
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
