---
id: lgu-01m147n30cnf
title: A per-file regions query for editors
status: closed
type: feature
priority: 2
mode: afk
created: '2026-08-28T13:06:25.932820481Z'
updated: '2026-09-09T01:42:10.227244634Z'
closed: '2026-09-09T01:42:10.227244634Z'
acceptance:
- title: '`legu regions <path> --json` returns structured current anchors, state, reason, original provenance and independently anchored ticket references.'
  done: true
- title: Integration tests cover unchanged, stale, shifted and renamed regions, overlapping review records and copies that inherit no review state.
  done: true
- title: Binary, empty, untracked, ignored, missing and unreadable files have the documented answers; invalid targets fail clearly.
  done: true
- title: Unreadable sidecars produce exit 0 and repository-relative `errors[]`; incomplete state is distinguishable from unreviewed content.
  done: true
- title: The human renderer exposes the same information and reports sidecar errors on stderr.
  done: true
- title: Emacs `legu-describe-region` uses the query and shows provenance at current anchors; tests cover overlaps and invalidated asynchronous answers.
  done: true
- title: On a reproducible 700-file fixture, the query is faster than path-scoped `status --json`; record both median timings and the measurement method on the ticket.
  done: true
deps:
- lgu-01m147kahq96
external_refs:
- git:b36df2c02f67ac5b79604d6105a56d4c781fb9f8
---

## Description

Add `legu regions <path>` so an editor can inspect one file's anchored review records and ticket references without computing repository-wide coverage.

Answer by current path, following the CLI's existing anchoring semantics, including renames and overlapping review records. JSON returns the repository-relative path, eligibility, total, review records and independent ticket references. Each anchored record carries structured current bounds, state, reason and original provenance: recorded path and bounds, commit, reviewer and timestamp. Preserve overlapping records individually; gaps are unreviewed.

Binary and empty files have null bounds and total 1; opaque is a property, not a review state. Existing untracked or ignored files return their records with eligibility false and an exclusion reason. Missing or unreadable files report their condition and any remaining missing records, with total 0. Invalid targets, directories and paths outside the repository fail clearly.

Follow the existing read-command error contract for unreadable sidecars. Report incomplete answers explicitly so clients cannot mistake unknown review state for unreviewed content. Provide a human-readable rendering of the same information.

Make Emacs `legu-describe-region` query this command asynchronously for the saved file. Show state, reason, provenance and ticket references at the current anchored location. Show every overlapping review record covering point. Reject answers invalidated by buffer edits or a newer request.

Keep repository snapshot formats and immediate local painting intact. Automatic painting on file opening remains the scope of the existing dependent ticket.

## Notes

**2026-09-09T01:36:30.824787849Z**

Performance check on 2026-09-09: created a fresh Git repository with one shared 200-line blob checked out as 700 tracked files, then marked files/file0350.txt:50-150. After one warm-up of each command, measured 11 sequential wall-clock runs with date +%s%N and took the sixth sorted value. legu regions files/file0350.txt --json had a 60 ms median (runs: 60,67,56,55,52,77,70,60,54,60,64). legu status files/file0350.txt --json had a 291 ms median (runs: 293,323,308,291,297,281,293,286,287,291,288). Same executable and warm filesystem cache for both.

**2026-09-09T01:42:10.227244634Z**

Added the per-file regions query, documented JSON and human contracts, integrated asynchronous Emacs provenance at current anchors, covered edge cases, and measured a 60 ms median against 291 ms for path-scoped status.
