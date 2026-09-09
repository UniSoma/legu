---
id: lgu-01m23a8m1t5c
title: Characterize today's CLI behavior in a runnable suite
status: closed
type: task
priority: 1
mode: afk
created: '2026-09-09T14:48:30.522532985Z'
updated: '2026-09-09T15:19:41.329769948Z'
closed: '2026-09-09T15:19:41.329769948Z'
parent: lgu-01m238vjgnh6
acceptance:
- title: A suite runs the real legu script as a subprocess and asserts on stdout, stderr and exit code
  done: true
- title: It runs with babashka alone, needs no emacs, and one documented command runs it and exits non-zero on failure
  done: true
- title: 'Every parity item the epic lists is covered by a case: -- terminator, --json=false, --no-json, options before the command, bare legu, --version in human and --json form'
  done: true
- title: Per-command argument-count errors, unknown option and unknown command errors are covered with their exact message text
  done: true
- title: --order and --limit validation is covered, including --limit 0 and a non-numeric --limit
  done: true
- title: A path:start-end target, a path containing a colon, and a path starting with a hyphen after -- are covered
  done: true
- title: The suite passes against the current unmodified legu script
  done: true
- title: The README or emacs/README documents how to run it alongside the ERT suite
  done: true
---

## Description

The only test suite legu ships is the Emacs ERT one in `emacs/legu-tests.el`, and it needs an emacs on PATH. There is none in the environment this epic will be implemented in, and its CLI-driving tier covers only what the Emacs package calls. So "behavior unchanged" — the promise the babashka.cli move rests on — has nothing to check it.

Record today's parser behavior as a runnable suite before anything moves, so the rewrite has a seam. Written against the CLI as a black box: run the `legu` script, assert on stdout, stderr and exit code. The epic's parity list is the checklist — the `--` terminator, `--json=false`, `--no-json`, options before the command, a bare `legu`, `legu --version` in both forms, per-command argument counts, unknown option and unknown command errors, `--order` and `--limit` validation, and `path:start-end` targets including a path holding a colon.

This suite is what phases 2, 3 and 4 of the epic run to prove they changed nothing they did not mean to. Where a later ticket deliberately changes behavior — scoping an option to its command turns an accepted line into an error — that ticket edits the recorded expectation and says so in its close summary.

## Notes

**2026-09-09T15:19:41.329769948Z**

test/cli_test.clj, 25 tests and 98 assertions, run with `bb test/cli_test.clj`. It drives the real script as a subprocess with babashka.process/sh and asserts exit code, stdout and stderr together, so a case cannot pass on the right message and the wrong exit code. A shared fixture builds a committed git tree in a temp dir with a fixed reviewer, fixed contents and fixed commit dates, so nothing asserted depends on the ambient git config or the clock.

Two of the epic's parity claims were wrong and the suite records what actually happens, not what the epic said. --no-json is `legu: unknown option: --no-json`, exit 1 — this parser has no negation at all; babashka.cli adds the spelling rather than preserving it. And `legu status --limit 3` is accepted and silently ignored, exit 0; the case carries a comment naming lgu-01m238wskh6s as the ticket that will turn it into an error, so that edit reads as intended rather than as a loosened test.

The bare-legu and --help case pins that the three spellings agree, the first line, and that every command and option name appears, rather than the usage blob verbatim: the blob is regenerated from the dispatch spec in lgu-01m238wawfq7, so a verbatim pin would fail there while saying nothing about behavior.

Documented under ## Tests in the root README, linked to the ERT suite's own docs.

Reviewed: extracted the repeated "succeeded and printed the same thing" assertion into prints-the-same-as, moved temp-dir cleanup into a finally so a load-time throw cannot leak it, and dropped the hard-coded 'user from run-tests.
