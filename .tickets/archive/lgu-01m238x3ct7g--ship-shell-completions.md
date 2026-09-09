---
id: lgu-01m238x3ct7g
title: Ship shell completions
status: closed
type: task
priority: 2
mode: afk
created: '2026-09-09T14:24:44.442827205Z'
updated: '2026-09-09T16:25:59.213688563Z'
closed: '2026-09-09T16:25:59.213688563Z'
parent: lgu-01m238vjgnh6
acceptance:
- title: legu org.babashka.cli/completions snippet --shell <shell> emits a working snippet for bash, zsh and fish
  done: true
- title: Completion offers legu's command names
  done: true
- title: Completion offers only the options the command in question accepts
  done: true
- title: Completion offers dir and cochange as values for --order
  done: true
- title: The README documents installation with one pasteable line per supported shell
  done: true
- title: Completion was exercised in a real interactive shell, not only by inspecting the emitted snippet
  done: true
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

## Notes

**2026-09-09T16:25:59.213688563Z**

`legu` itself was not touched. babashka.cli's dispatch provides the completions command as soon as :prog is set, which lgu-01m238wawfq7 already did, so this ticket is the outside check on lgu-01m238wskh6s's per-command spec rather than a feature to build.

That check passes: for all eight commands, every candidate completion offers was run against the command it was offered for, and none was refused. No positional key (--target, --path, --id) leaks in as an option. --order offers dir then cochange, in the enum's declared order.

One correction to the plan: its expected option lists omitted --version, which completion offers on every command and every command accepts. The spec was right; the plan's table was incomplete.

Criterion 6, the honest version: zsh is driven interactively — zsh -i on a pseudo-terminal via zsh/zpty, the snippet sourced from a .zshrc, a literal TAB sent, and the painted menu read back. bash sources the snippet and is asked what it would have offered; fish is asked through `complete -C` against the file the README installs. All three drive real completion machinery, but only zsh is an interactive shell, and the README now says so rather than claiming otherwise. powershell and nushell emit snippets that were not exercised; the README says that too.

Review found the README's fish line did not work as written: fish does not create ~/.config/fish/completions, so the pasteable line failed with `warning: Path … does not exist` and wrote nothing. The suite had hidden it by creating the directory itself. The line now carries the mkdir -p, and was pasted verbatim into a fresh HOME to confirm.

Review also found three ways these tests could report green without checking anything, all fixed: a missing shell printed a skip note and passed, so a shell absent in CI was indistinguishable from one that answered — it now fails, naming the shell; complete_in_zsh.zsh exited 0 whether or not zsh ever started, so it now dies when the pty produces nothing; and the zsh case's substring assertions were satisfied by an empty screen, so blank output is now ruled out once before them, and each command is checked not to offer the options another command owns.

Sensitivity checked both ways: giving status a --limit it does not read fails 7 assertions across the callback and all three shells, and hiding zsh and fish from PATH fails 2.

Suite: 36 tests, 227 assertions, green. Linter at its two-finding baseline.
