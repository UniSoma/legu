---
id: lgu-01m28sh82tk1
title: Sign review records with a per-user Ed25519 key
status: closed
type: feature
priority: 2
mode: afk
created: '2026-09-11T17:51:33.978416771Z'
updated: '2026-09-11T20:05:57.424802139Z'
closed: '2026-09-11T20:05:57.424802139Z'
tags:
- ready-for-agent
- signing
---

## Description

### Problem Statement

A review record says who reviewed a region, but nothing in the store backs that up. The `reviewer` field is whatever `git config user.name` or `--reviewer` said, so anyone with push access can add a record claiming a colleague reviewed a region they never opened, or edit the region, timestamp or hashes of a genuine record, and no reader of the store can tell. A team that wants to rely on coverage numbers cannot know for sure that a mark was made by the person it names.

### Solution

A store can be **signed**. In a signed store every review record carries a **signature**: an Ed25519 signature over the record's own canonical line, produced by the reviewer's **signer** key. A committed **signers list** in the store binds each signer to a reviewer name; its presence is what turns signing on. `legu mark` in a signed store refuses to write a record it cannot sign with a listed key, and takes the reviewer name from the signers list rather than from git. A new `legu verify` reports every record whose signature does not hold, whose signer is unlisted, whose name disagrees with the signers list, or which is unsigned in a signed store. Reading commands trust the store as they do today. Stores without a signers list behave exactly as before.

This implements [ADR-0016](../docs/adr/0016-signed-review-records.md); the terms are in the Signing section of CONTEXT.md.

### User Stories

1. As a reviewer, I want to generate a signing key once on my machine, so that every repository I review in can carry my signature.
2. As a reviewer, I want `legu key init` to refuse to overwrite a key that already exists, so that I cannot lose the key my existing records were signed with by accident.
3. As a reviewer, I want `legu key show` to print my public key as a signers-list line, so that I can hand it to a repository I cannot push to.
4. As a repository maintainer, I want `legu key add` to append my public key and name to the store's signers list, creating the list if absent, so that turning signing on for the repo is one deliberate commit.
5. As a repository maintainer, I want `legu key add` to be idempotent for a key already listed, so that running it twice does not duplicate a line.
6. As a repository maintainer, I want `legu key add` to refuse when the same key is already listed under a different name, so that one key never binds to two reviewers.
7. As a reviewer with two machines, I want to list two keys under my one name, so that marks from either machine verify as mine.
8. As a reviewer in a signed store, I want `legu mark` to sign the record with my key automatically, so that signing costs me nothing in the reading loop.
9. As a reviewer in a signed store, I want `legu mark` to take my reviewer name from the signers list entry for my key, so that a record can never be written that verify would reject.
10. As a reviewer in a signed store, I want `legu mark --reviewer` to be an error that says why, so that I do not silently produce a record under a name my key does not vouch for.
11. As a reviewer in a signed store without a key, I want `legu mark` to fail with a message naming `legu key init`, so that I know what to do next.
12. As a reviewer in a signed store whose key is not listed, I want `legu mark` to fail with a message naming `legu key add`, so that I know what to do next.
13. As a reviewer in an unsigned store, I want `legu mark` to behave exactly as it does today, so that trying legu on a scratch repo needs no key.
14. As a reviewer, I want a mark in a signed store to still be a one-line change to the sidecar, so that a review-heavy commit's store diff stays as small as it is today.
15. As a reviewer, I want the signature to sit at the end of the record line after the hashes, so that the region, name and timestamp still sit in the first sixty columns.
16. As a reviewer, I want the same store state to render as the same bytes whether records were signed on one machine or another, so that two clones do not conflict on formatting.
17. As a teammate, I want `legu verify` to report every review record in the store that is not valid, with the sidecar path, the region and the reason, so that I can find a forged or damaged record.
18. As a teammate, I want `legu verify <path>` to check one file or directory, so that a check on a large repo can be scoped.
19. As a teammate, I want `legu verify` to distinguish a bad signature, an unlisted signer, a name that differs from the one the signers list gives the key, and an unsigned record in a signed store, so that I know whether I am looking at tampering, a missing onboarding step, or a record from before signing was turned on.
20. As a teammate, I want `legu verify` to exit non-zero when any record is not valid and zero when all are, so that CI can gate on it.
21. As a teammate, I want `legu verify --json` to emit the same findings as data, so that tooling can consume them.
22. As a teammate, I want `legu verify` in an unsigned store to say the store is not signed and exit zero, so that the command is safe to run anywhere.
23. As a teammate, I want `legu verify` to report a signers-list line it cannot parse, so that a broken trust root is not mistaken for a broken record.
24. As a reader, I want `status`, `stale`, `next`, `regions` and `coverage` to run without verifying signatures, so that reading commands stay as fast as they are today.
25. As a reader, I want a record whose signature would fail verification to still count as reviewed or stale in the reading commands, so that a verification problem is a report on the store and not a change to my coverage.
26. As a reviewer, I want forget and supersede to work on any record regardless of who signed it, so that a signature proves origin and not permanence.
27. As a reviewer, I want ticket references to stay unsigned, so that anchoring a ticket does not need a key.
28. As a reviewer, I want `legu --version` to report store schema 4, so that a client knows what it will read.
29. As a reviewer opening an old schema 3 store, I want the CLI to refuse it with a message naming the schema it writes, so that a stale store is never misread.
30. As an Emacs user, I want the package to read schema 4 sidecars and refuse schema 3 the way it refuses schema 2 today, so that the editor and CLI agree.
31. As an Emacs user, I want `legu-mark` to keep issuing one `legu mark`, so that signing happens in the CLI and the editor never touches a key.
32. As an Emacs user in a signed store without a key, I want the CLI's error to surface in the editor the way other mark errors do, so that I learn what to configure.
33. As a reviewer, I want my private key stored under my user config directory with owner-only permissions and no passphrase, so that a mark never prompts and the key is not readable by other accounts on the machine.
34. As a reviewer, I want the key location to honour `XDG_CONFIG_HOME` and fall back to `~/.config`, so that my setup follows the convention my other tools use.
35. As a reviewer, I want `legu --help` and `legu key --help` and `legu verify --help` to list the new commands and their options, so that they are discoverable.
36. As a shell user, I want tab completion to offer `key`, `verify` and their subcommands and options, so that completion stays right as legu grows.
37. As a contributor, I want the README to document signing: turning it on, the key commands, verify, the exact bytes signed and the limit that a listed key is only as trustworthy as the commit that listed it, so that the feature is understood before it is relied on.
38. As a contributor, I want the domain prefix over the signed bytes to be fixed and documented, so that a signature can never be replayed as a signature over anything but a legu record and so that a third party can verify a record with no legu at hand.

### Implementation Decisions

- **Store layout** follows ADR-0017: sidecars under `sidecars/` inside the store, the ignore list at `ignore`, the signers list at `signers`, and only the sidecars marked generated. The move is its own ticket ahead of this work.
- **Cryptography** is the JDK's Ed25519 as shipped in babashka: key generation, signing and verification are library calls. No `ssh-keygen`, no `gpg`, no new runtime dependency beyond git.
- **Sidecar schema** bumps to 4. Schema 3 is refused, not migrated, as every earlier schema was. The header line stays `{"schema":4}`. The Emacs schema constant moves to 4.
- **Record shape.** A review record gains one optional key, `signature`, base64 of the 64 raw signature bytes, rendered last in the fixed key order: region, reviewer, timestamp, commit, file hash, content hash, signature. Ticket references never carry it. Record ordering keeps the existing rule, sorted by region then every remaining field in key order; the signature participates as the last tie-breaker so identical state is identical bytes.
- **Bytes signed.** A fixed domain string, `legu-review-record` followed by a newline, then the record line rendered exactly as it is stored minus the `signature` key. Any change to the line, including its key order, is a schema change.
- **Signers list.** A file named `signers` at the root of the store, one line per key: the public key as base64 of the 32 raw bytes, a single space, then the reviewer name to end of line. Blank lines and lines starting with `#` are ignored. A key appears at most once. A name may appear on several lines. The file is what makes a store signed; there is no other switch.
- **Store is signed** iff the signers list exists. In a signed store: `mark` requires a local key whose public half is listed, derives the reviewer name from that line, rejects `--reviewer` with an error, and writes a signed record. In an unsigned store `mark` is unchanged and writes no signature.
- **Private key** lives at `<config>/legu/key` with `<config>/legu/key.pub` beside it, where `<config>` is `$XDG_CONFIG_HOME` or `~/.config`. The private file is the 32-byte seed base64 on one line, created with mode 0600; the public file is the signers-list key half on one line. No passphrase.
- **Key commands** under one `key` command with subcommands `init`, `show`, `add`. `init` creates the pair and refuses if the private file exists. `show` prints the signers-list line the local key would add, using `git config user.name` for the name. `add` appends that line to the store's signers list, creating the file, no-op if the exact line exists, error if the key exists under another name. Each command has `--json` output like the others.
- **Verify command.** `legu verify [<path>]` walks the sidecars under the path, or the whole store, and for each review record reports one of: `valid`, `bad-signature`, `unlisted-signer`, `name-mismatch`, `unsigned`. A signers-list line that does not parse is reported once as a store-level finding. Human output lists only records that are not valid, one line each with sidecar path, region, reviewer and reason, and a summary count; `--json` emits every finding. Exit 1 if any record is not valid, else 0. In an unsigned store it prints that the store is not signed and exits 0. Verification of an ed25519 signature is a function call, so no caching is needed.
- **Reading commands** do not verify. A record's `signature` is carried through load, supersede, forget and rename-following untouched, and never inspected outside `verify`.
- **Signer identity in verification** is the public key; the reviewer name on the record must equal the name on the signers line for that key, else `name-mismatch`. Verification against a key the local machine does not have works, since only public keys are needed.
- **Command-line table.** The new commands and options join the single table that drives parsing, help and shell completion, so completion and `--help` follow without extra work. Options belong to their command: `verify` takes only the path argument.
- **Errors** follow the existing shape: exit 1, `legu: <message>` on stderr, nothing on stdout. Messages name the next command to run where there is one.
- **Emacs** changes only the schema constant and its tests. The optimistic paint on mark is unchanged; a CLI error on mark surfaces as it does today.

### Testing Decisions

- A good test drives the real script from a scratch git repo and asserts on exit code, stdout and stderr, never on internal functions. The one seam is the existing black-box CLI suite, which already builds a committed fixture repo per case with a fixed reviewer and fixed dates. Cases for this feature also set `XDG_CONFIG_HOME` to a directory inside the scratch tree, so no test reads or writes the developer's real key.
- Cover, at that seam: key init creates both files with the right mode and refuses a second time; show prints a line that add appends; add is idempotent and rejects a second name for one key; mark in an unsigned store writes no signature and the sidecar is byte-identical to today's; mark in a signed store writes a signature that verify accepts, refuses `--reviewer`, fails without a key, fails with an unlisted key, and uses the listed name; the record is one line and the signature is the last key; verify reports each of the five outcomes on hand-edited sidecars, including one where a hash was altered under a valid signature and one where the name was changed; verify exits non-zero on any failure, zero on a clean or unsigned store; `--json` shape; schema 3 refused; `--version` says 4; completion lists the new commands; the same signed state renders as the same bytes.
- Prior art: the existing cases for `mark`, `forget`, the `--version` handshake, the fixed-layout byte-equality case, and the completion cases in the CLI suite. Sidecar tampering is done by rewriting the file in the scratch repo, as the corrupt-sidecar cases already do.
- Emacs: the ERT schema-gate and version-handshake cases move to schema 4; no new ERT cases are needed since the editor does not read the signature.

### Out of Scope

- Reusing git or SSH signing keys, or any external signing tool.
- Passphrase-protected keys, key rotation or revocation, key expiry.
- Verifying on read, or letting verification change what a reading command reports.
- Protecting records from forget or supersede by other reviewers.
- Signing ticket references.
- Trusted timestamps; the timestamp stays self-asserted.
- Any defence against a push-access user adding their own key under another name to the signers list; that is a reviewable diff to one file and stays so.
- Showing the signer in `status` or the Emacs views.
- Migration from schema 3.

### Further Notes

The signature says who marked, not who read. Nothing in this design changes that.

The signers list is the trust root and the switch. A repo that lists keys but has records from before the list existed will see them reported as `unsigned` by verify; re-marking those regions is the way to sign them.

## Notes

**2026-09-11T20:05:57.424802139Z**

Signed review records landed in four slices: the store moved under .review (56a7400), legu key init/show/add (a8d0138), signed marks at sidecar schema 4 (02e9cfc), and legu verify (f9178cb). A store with .review/signers is signed; every mark in it carries an Ed25519 signature over the documented bytes, and verify reports every record whose signature does not hold.
