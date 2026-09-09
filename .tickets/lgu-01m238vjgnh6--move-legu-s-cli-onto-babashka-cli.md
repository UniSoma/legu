---
id: lgu-01m238vjgnh6
title: Move legu's CLI onto babashka.cli
status: open
type: epic
priority: 2
mode: hitl
created: '2026-09-09T14:23:54.389589203Z'
updated: '2026-09-09T14:23:54.389589203Z'
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
