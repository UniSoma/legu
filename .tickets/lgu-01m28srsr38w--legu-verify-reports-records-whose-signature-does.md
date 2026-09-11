---
id: lgu-01m28srsr38w
title: legu verify reports records whose signature does not hold
status: open
type: feature
priority: 2
mode: afk
created: '2026-09-11T17:55:41.440534575Z'
updated: '2026-09-11T17:55:59.353047383Z'
parent: lgu-01m28sh82tk1
tags:
- ready-for-agent
- signing
acceptance:
- title: verify exits 1 on any failure, 0 on a clean store and 0 with a message on an unsigned store; a path argument scopes the walk
  done: false
- title: --json emits every finding; help and completion list verify
  done: false
- title: Reading commands do not verify and still count a record that would fail
  done: false
- title: README documents verify and the trust limit of the signers list
  done: false
- title: verify reports each of bad-signature, unlisted-signer, name-mismatch and unsigned on hand-tampered sidecars, and a store-level finding for an unparseable signers line
  done: false
deps:
- lgu-01m28srsmekn
---

## Description

Parent: lgu-01m28sh82tk1.

### What to build

`legu verify [<path>]` walks the sidecars under the path, or the whole store, and checks every review record against the signers list. Each record is one of: valid, bad-signature, unlisted-signer, name-mismatch (the record's reviewer differs from the name the signers list gives that key), or unsigned (no signature in a signed store). A signers-list line that does not parse is reported once as a store-level finding. Human output lists only records that are not valid, one line each with sidecar path, region, reviewer and reason, then a summary count. `--json` emits every finding. Exit 1 if any record is not valid, else 0. In an unsigned store it says the store is not signed and exits 0. Only public keys are needed, so a machine with no local key can verify. Reading commands are untouched: status, stale, next, regions and coverage never verify and a record that would fail still counts as reviewed or stale.

Tests tamper with sidecars in the scratch repo by rewriting them, as the corrupt-sidecar cases do: a hash edited under a valid signature, a reviewer name changed, a signature from a key not in the list, a record with the signature removed. The README documents verify, the CI use of its exit code, and the limit that a listed key is only as trustworthy as the commit that listed it, the same limit git's allowed_signers has.

### Blocked by

- lgu-01m28srsmekn
