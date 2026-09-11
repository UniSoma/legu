---
id: lgu-01m28srsmekn
title: Signed marks and sidecar schema 4
status: open
type: feature
priority: 2
mode: afk
created: '2026-09-11T17:55:41.318535816Z'
updated: '2026-09-11T17:55:59.245767549Z'
parent: lgu-01m28sh82tk1
tags:
- ready-for-agent
- signing
acceptance:
- title: Mark in a signed store takes the name from the signers list, rejects --reviewer, and fails naming key init or key add when the key is missing or unlisted
  done: false
- title: Mark in an unsigned store writes a sidecar identical to today's apart from the schema 4 header
  done: false
- title: Schema 3 is refused by CLI and Emacs; --version reports schema 4; the same signed state renders as the same bytes
  done: false
- title: Forget and supersede on signed records keep the signature of records they leave in place
  done: false
- title: README documents the bytes signed and marking in a signed store
  done: false
- title: Mark in a signed store writes a record whose last key is signature, verifiable against the listed public key over the documented bytes
  done: false
deps:
- lgu-01m28srsgket
---

## Description

Parent: lgu-01m28sh82tk1.

### What to build

In a signed store, one with a signers list, `legu mark` writes a signed review record. The signature is Ed25519 over a fixed domain string, `legu-review-record` plus a newline, followed by the record line exactly as stored minus the `signature` key. It is stored as base64 of the 64 raw bytes under the key `signature`, rendered last in the fixed key order after the content hash, so a mark is still a one-line diff and the region, name and timestamp keep the first sixty columns. The reviewer name comes from the signers line for the local key; `--reviewer` is an error in a signed store. Without a local key the error names `legu key init`; with a key not in the signers list it names `legu key add`. In an unsigned store mark is unchanged and writes no signature. Record ordering keeps the existing rule with signature as the last tie-breaker so identical state is identical bytes.

The sidecar schema becomes 4 in the CLI and in the Emacs package; schema 3 is refused, not migrated, with the existing message shape; `legu --version` reports 4. Load, supersede, forget and rename-following carry the signature through untouched and never inspect it. Ticket references never carry one. Emacs changes only its schema constant and the two ERT cases that pin it; `legu-mark` still issues one `legu mark`. The README documents the exact bytes signed and how mark behaves in a signed store.

### Blocked by

- lgu-01m28srsgket
