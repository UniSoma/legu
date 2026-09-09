# Issue tracker: knot

Issues for this repo are knot tickets: markdown files with YAML frontmatter under `.tickets/`, managed only through
the `knot` CLI. Config is `.knot.edn` (prefix `lgu`, statuses `open → in_progress → closed`, types
`bug feature task epic chore`, modes `afk hitl`). Ids look like `lgu-01<base32>`; a 6–8 character suffix resolves.

The `knot` skill (`.claude/skills/knot/`) is the authoritative guide to the CLI. Read it before touching tickets.
`.tickets/` is an implementation detail: never `cat`, `grep`, `ls`, write, or `mv` those files directly — every read
and write goes through a `knot` command, and every command takes `--json` for decision logic.

## Conventions

- **Spec**: an `epic` ticket. The spec text is its description; implementation tickets are its children.
- **Implementation issue**: one ticket per unit of work, created with `--parent <epic-id>`. Use `knot dep <a> <b>`
  when `a` must wait on `b`; `knot ready` then surfaces only unblocked work.
- **Acceptance criteria**: `--acceptance` (repeatable) on create, `--add-ac` later. Never a hand-written
  `## Acceptance Criteria` section — it doesn't sync, and `knot close` gates on the frontmatter list.
- **Comments / history**: `knot add-note <id> "…"` — timestamped, append-only. Never edit the body to add history.
- **Agent-runnable?**: the `mode` field. `afk` = an agent can run it end to end; `hitl` (default) = a human is in the
  loop. `knot ready --mode afk` is the autonomous queue. `afk` is also the `ready-for-agent` triage state; see `triage-labels.md`.
- **Closing**: always `knot close <id> --summary "<what shipped>"`, plus `--external-ref git:<full-sha>` when a commit
  finished it.

## When a skill says "publish to the issue tracker"

```sh
# spec
knot create "<feature title>" -t epic --description "$(cat <<'MD'
…spec body…
MD
)" --json | jq -r '.data.id'

# implementation ticket under that epic
knot create "<title>" -t task --parent <epic-id> --description "…" --acceptance "…" --acceptance "…" --json
```

Set `--mode afk` only when the ticket is fully specified; set `-p` (0 = highest, default 2) when priority is known.

## When a skill says "fetch the relevant ticket"

`knot show <id>`. For everything around it: `knot list --parent <id>` (children),
`knot list --closure <id>` (live tickets transitively related), `knot dep tree <id>` (what it waits on).
The closure walks the archive to find its edges but `list` renders only live tickets: to see the closed ones
it reached, run `knot closed --closure <id>`.

## When a skill says "comment on the ticket"

`knot add-note <id> "…"` (multi-line via a quoted heredoc on stdin). Triage disclaimers go at the top of the note.

## Wayfinding operations

Used by `/wayfinder`. The **map** is an `epic` ticket; each **child** ticket is a question.

- **Map**: the epic's body holds Notes / Decisions-so-far / Fog. Update with `knot update <id> --description`.
- **Child ticket**: `knot create "<question>" --parent <map-id> --tags wayfinder,<type>` where `<type>` is one of
  `research` / `prototype` / `grilling` / `task`. The question is the description.
- **Blocking**: `--dep <other-child>` on create (repeatable), or `knot dep <child> <other-child>` later. A ticket is unblocked when `knot ready` lists it.
- **Frontier**: `knot ready --parent <map-id> --assignee "" --json`, oldest `created` first.
- **Claim**: `knot start <id> --assignee <you> --if-unassigned` before any work.
- **Resolve**: `knot close <id> --summary "<the answer>"`, then append a context pointer (gist + id) to the map's
  Decisions-so-far.

## PRs as a request surface

Off. There is no remote; external PRs are not part of the triage queue.
