# Triage Labels

The skills speak in terms of two category roles and five state roles. knot has native fields for most of them, so a
role is applied through the field that owns it, not as a free-text label.

## Category roles → `type`

| Role          | knot                          |
| ------------- | ----------------------------- |
| `bug`         | `--type bug`                  |
| `enhancement` | `--type feature`              |

Set on create, or `knot update <id> --type <t>`.

## State roles → `tags` and `mode`

| Role in mattpocock/skills | In our tracker             | Meaning                                  |
| ------------------------- | -------------------------- | ---------------------------------------- |
| `needs-triage`            | tag `needs-triage`         | Maintainer needs to evaluate this issue  |
| `needs-info`              | tag `needs-info`           | Waiting on reporter for more information |
| `ready-for-agent`         | `--mode afk` (no tag)      | Fully specified, ready for an AFK agent  |
| `ready-for-human`         | tag `ready-for-human`      | Requires human implementation            |
| `wontfix`                 | tag `wontfix`, then close  | Will not be actioned                     |

`ready-for-agent` has no tag because `mode afk` already carries that exact meaning and `knot ready --mode afk` is
the agent queue. `ready-for-human` needs a tag because `hitl` is the default mode: an untriaged ticket is also
`hitl`, so mode alone can't tell "decided: needs a human" from "nobody has looked yet".

A ticket carries at most one state tag, and a ticket with a state tag is never `afk`. Transition with the delta
flags so nothing else on the ticket is lost:

```sh
knot update <id> --remove-tag needs-triage --mode afk                     # → ready-for-agent
knot update <id> --remove-tag needs-triage --add-tag ready-for-human      # → ready-for-human
knot update <id> --add-tag wontfix && knot close <id> --summary "<why>"   # → wontfix
```

Never pass `--tags` to change one tag — it replaces the whole list.

## Queries the triage skill needs

```sh
knot list --mode hitl --json | jq '[.data[] | select(([.tags[] | select(test("^(needs-triage|needs-info|ready-for-human|wontfix)$"))] | length) == 0)]'   # unlabeled: hitl and no state tag
knot list --tag needs-triage
knot list --tag needs-info          # re-check ones with notes newer than the last triage note
knot ready --mode afk               # what agents can pick up
```
