---
id: lgu-01m238x3ct7g
title: Ship shell completions
status: open
type: task
priority: 2
mode: afk
created: '2026-09-09T14:24:44.442827205Z'
updated: '2026-09-09T14:48:45.740141748Z'
parent: lgu-01m238vjgnh6
acceptance:
- title: legu org.babashka.cli/completions snippet --shell <shell> emits a working snippet for bash, zsh and fish
  done: false
- title: Completion offers legu's command names
  done: false
- title: Completion offers only the options the command in question accepts
  done: false
- title: Completion offers dir and cochange as values for --order
  done: false
- title: The README documents installation with one pasteable line per supported shell
  done: false
- title: Completion was exercised in a real interactive shell, not only by inspecting the emitted snippet
  done: false
deps:
- lgu-01m238wawfq7
- lgu-01m238wskh6s
---

## Description

Once the dispatch tree exists, babashka.cli can emit shell completion snippets from it for free, through the hidden
`org.babashka.cli/completions` command:

    legu org.babashka.cli/completions snippet --shell bash

bash, zsh, fish, powershell and nushell are all supported. This was verified working on the prototype tree.

The snippet completes command names, option names and enum values, all derived from the same spec that parses them, so
it stays correct on its own as legu grows options. legu has no way to offer completion today at any price, which makes
this the one item in the epic that adds a capability rather than consolidating one.

This ticket waits only on the dispatch move, so it can run alongside the tightening ticket. But the two do interact:
until per-command scoping lands, completion offers every option on every command, and until `--order` becomes an enum
there are no values to complete for it. If this ticket is picked up first, complete command and option names and leave
the enum values to follow; if the tightening has already landed, both come for free. Either way, completion must never
offer an option the command would reject — that is worse than offering nothing.

Installation belongs in the README beside the existing single-line install instructions, kept to the one line per shell
that a user pastes into a shell init file.
