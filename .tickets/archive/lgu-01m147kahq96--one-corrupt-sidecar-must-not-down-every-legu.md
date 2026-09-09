---
id: lgu-01m147kahq96
title: One corrupt sidecar must not down every legu command
status: closed
type: bug
priority: 1
mode: afk
created: '2026-08-28T13:05:28.119662400Z'
updated: '2026-09-09T00:53:41.193935190Z'
closed: '2026-09-09T00:53:41.193935190Z'
acceptance:
- title: A repo with one unparseable sidecar still reports coverage, status, stale and next for every other file, exit 0
  done: true
- title: Read commands list the unreadable sidecars under an `errors` key in --json, repo-root-relative, omitted when empty
  done: true
- title: A write whose target sidecar is the broken one still fails loudly rather than dropping state
  done: true
- title: The human renderer still names the offending file on stderr
  done: true
- title: The Emacs queue banner is driven by `errors[]` rather than by matching stderr text
  done: true
external_refs:
- git:7c86e1c9da099e6e55c2f6ae64cae837f5c24aa9
---

## Description

`.review/` is committed alongside the code, so merge conflicts in sidecars are
expected. Today any malformed sidecar makes the CLI exit 1 with empty stdout —
from *every* command, including ones that never needed to read that file. One
bad file and `status`, `stale`, `coverage`, `next`, `mark`, `note` and `forget`
are all dead until a human finds and fixes it.

A read command should skip the sidecar it cannot parse, answer for everything
else, exit 0, and report the failure as data. A write command should still
refuse when the *target* sidecar is the broken one — that write would lose
state.

Read commands gain one optional key in their `--json` object, omitted when
empty, repo-root-relative (today's stderr path is absolute):

    {"files": [...], "notes": [...],
     "errors": [{"file": ".review/src/core.clj.edn",
                 "reason": "not a review record"}]}

The human renderer keeps mirroring these to stderr as it does now.

The Emacs package already detects this state by matching stderr and shows a
banner from the last good snapshot; it should read `errors[]` instead and keep
every other number live.

## Notes

**2026-09-09T00:53:41.193935190Z**

Read commands skip a sidecar they cannot parse, answer for every other file and list the skipped ones under an errors key; writes to the unreadable sidecar still refuse; the Emacs banner reads errors[] and keeps its numbers live.
