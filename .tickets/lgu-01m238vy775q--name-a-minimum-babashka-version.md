---
id: lgu-01m238vy775q
title: Name a minimum babashka version
status: open
type: task
priority: 2
mode: afk
created: '2026-09-09T14:24:06.375760005Z'
updated: '2026-09-09T14:25:15.353656696Z'
parent: lgu-01m238vjgnh6
acceptance:
- title: README's Requirements section names a minimum babashka version instead of "babashka and git. Nothing else."
  done: false
- title: legu checks the running babashka version at startup and dies through the existing die path with a message naming the required version and the one it found
  done: false
- title: 'The message is legible to a human upgrading: it says what to install, not which babashka.cli function was missing'
  done: false
- title: The version comparison handles the three-part version string correctly, including a component that is numerically greater but lexically smaller (1.13.9 vs 1.13.220)
  done: false
- title: The floor is verified by running legu against a babashka at that exact version, or the ticket records why 1.13.220 was used instead
  done: false
---

## Description

The README's Requirements section says "babashka and git. Nothing else." — no version floor at all. The rest of this
epic uses babashka.cli features that only exist in recent babashka, so the floor has to be named before anything else
can rely on it.

babashka 1.13.219 (2026-07-27) is the first release bundling babashka.cli 0.12.88. Every feature the epic uses is at or
below that version: auto-help (0.10.69), completions (0.12.70), `:positional` and `:restrict-args` (0.12.76), `:enum`
(0.12.80). babashka 1.12.218 (2026-04-20) is the previous release and predates all of them, so there is no 1.12.x that
would do.

Verify the floor against a real 1.13.219 rather than trusting the changelog. If a 1.13.219 cannot be obtained, set the
floor to 1.13.220 — the version the epic's findings were verified on — and say in the ticket why.

Without a runtime check, an old babashka fails somewhere deep in the parser with an arity or resolution error that
names babashka.cli rather than the real problem. `(System/getProperty "babashka.version")` returns the version string
and is the cheapest place to catch it, at startup, through legu's existing `die`.
