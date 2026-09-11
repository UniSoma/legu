---
id: lgu-01m28tewtjn0
title: Move everything legu owns under .review
status: open
type: chore
priority: 2
mode: afk
created: '2026-09-11T18:07:45.490878027Z'
updated: '2026-09-11T18:07:45.490878027Z'
parent: lgu-01m28sh82tk1
tags:
- ready-for-agent
- signing
acceptance:
- title: Sidecars are read and written under .review/sidecars/, mirroring the source tree
  done: false
- title: The ignore list is read from .review/ignore and .reviewignore is no longer consulted
  done: false
- title: .gitattributes marks only .review/sidecars/** generated
  done: false
- title: Emacs derives sidecar paths from the new location; ERT and the CLI suite pass
  done: false
- title: README, Emacs README and CONTEXT.md name the new locations; the repo's own store is moved
  done: false
---

## Description

Parent: lgu-01m28sh82tk1. Decision: ADR-0017.

### What to build

The store becomes the one directory for everything legu owns. Sidecars move from `.review/<path>.jsonl` to `.review/sidecars/<path>.jsonl`, so the mirror of the source tree lives one level down. The ignore list moves from `.reviewignore` at the repo root to `.review/ignore`, same gitignore syntax, same matching by git. The committed `.gitattributes` marks only `.review/sidecars/**` as generated, so files at the store's root, the ignore list and later the signers list, show in full in review views. The store's own files never count as eligible, as today. The CLI and the Emacs package derive sidecar paths from the new location and find the ignore list there; every reference in the README, the Emacs README and the glossary follows. No migration: there are no stores outside this repository, so the repository's own store is moved in the same commit. Behaviour is otherwise unchanged and every existing test passes against the new layout.

### Blocked by

None (can start immediately).
