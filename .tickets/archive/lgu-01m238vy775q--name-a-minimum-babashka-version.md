---
id: lgu-01m238vy775q
title: Name a minimum babashka version
status: closed
type: task
priority: 2
mode: afk
created: '2026-09-09T14:24:06.375760005Z'
updated: '2026-09-09T15:19:41.440266485Z'
closed: '2026-09-09T15:19:41.440266485Z'
parent: lgu-01m238vjgnh6
acceptance:
- title: README's Requirements section names a minimum babashka version instead of "babashka and git. Nothing else."
  done: true
- title: legu checks the running babashka version at startup and dies through the existing die path with a message naming the required version and the one it found
  done: true
- title: 'The message is legible to a human upgrading: it says what to install, not which babashka.cli function was missing'
  done: true
- title: The version comparison handles the three-part version string correctly, including a component that is numerically greater but lexically smaller (1.13.9 vs 1.13.220)
  done: true
- title: The floor is verified by running legu against a babashka at that exact version, or the ticket records why 1.13.220 was used instead
  done: true
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

## Notes

**2026-09-09T15:19:41.440266485Z**

The floor is babashka 1.13.220, checked at the top of -main through the existing die path, before *root* and *git?* are bound.

The epic's evidence was off. 1.13.219 bundles babashka.cli 0.12.85, not 0.12.88, and completions shipped in 0.11.70, not 0.12.70. 1.13.219 is still the earliest release carrying every feature the epic names, so it was a genuine candidate. 1.13.220 was chosen anyway: `Inherited options:` in generated help and format-command-help accepting :spec both arrived in babashka.cli 0.12.86, which ships in 1.13.220 and not 1.13.219, and lgu-01m238wawfq7's "help renders from the spec" leans on both. One release lower buys nothing and costs the help output.

Criterion 5 was met properly rather than through its escape hatch: babashka 1.13.219 was downloaded to a scratch directory and legu run under it, printing `legu: needs babashka 1.13.220 or newer, but found 1.13.219; install a newer babashka from https://babashka.org` and exiting 1, for both --version and status.

The comparison is a pure function, babashka-too-old, parsing components as longs and padding to equal width, so neither string order nor a differing component count decides it — 1.13.9 is older than 1.13.220, and 1.13 is older than both. A version string that does not split into numbers, such as a dev build, counts as new enough: refusing to run on a version legu cannot read would cost more than the check saves. Six cases cover it, including the lexical trap directly.

The script's tail is now guarded by (when (= *file* (System/getProperty "babashka.file")) ...) so the suite can load the file and call the comparison, which no subprocess can reach without a babashka installed at each version compared. Verified that ./legu, bb legu, a PATH shim and a symlink all still run.

emacs/README.md's Requirements list was left alone: legu.el shells out to the legu binary and never runs babashka itself, so naming the floor there would duplicate a fact that then has to be kept in step in two places.

Reviewed: the comment justifying the floor claimed legu already leans on babashka.cli, which is not true until lgu-01m238wawfq7 — reworded to say the floor lands ahead of that move. MIN-BB renamed MIN-BABASHKA to match the spelling used everywhere else.
