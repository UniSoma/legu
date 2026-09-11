---
id: lgu-01m28srsgket
title: 'Key commands: legu key init, show and add'
status: closed
type: feature
priority: 2
mode: afk
created: '2026-09-11T17:55:41.203877010Z'
updated: '2026-09-11T19:11:34.993068895Z'
closed: '2026-09-11T19:11:34.993068895Z'
parent: lgu-01m28sh82tk1
tags:
- ready-for-agent
- signing
acceptance:
- title: key init creates key and key.pub under XDG config, private file mode 0600, and refuses a second run
  done: true
- title: key show prints the signers line; key add creates or appends the signers file, is idempotent, and rejects a key under a second name
  done: true
- title: Help and completion list key and its subcommands; each subcommand supports --json
  done: true
- title: CLI suite covers the above with XDG_CONFIG_HOME inside the scratch repo
  done: true
- title: README documents the key commands and the signers-list format
  done: true
deps:
- lgu-01m28tewtjn0
---

## Description

Parent: lgu-01m28sh82tk1 (the spec; ADR-0016 and the Signing section of CONTEXT.md hold the terms).

### What to build

A reviewer generates a signing key once on their machine and registers it in a repository's store. `legu key init` creates an Ed25519 keypair under the user's config directory (`$XDG_CONFIG_HOME/legu`, falling back to `~/.config/legu`): the private file is the 32-byte seed base64 on one line with mode 0600, the public file the 32-byte public key base64 on one line. It refuses if the private file already exists. `legu key show` prints the signers-list line for the local key: public key base64, one space, then `git config user.name` to end of line. `legu key add` appends that line to `signers` at the root of the store, creating the file if absent; it is a no-op when the exact line is present and an error when the key is listed under a different name. Blank lines and lines starting with `#` in the signers list are ignored. Cryptography is the JDK's Ed25519 as shipped in babashka; no external tool.

The three subcommands join the command table so `--help`, per-command help and shell completion follow. Each has `--json`. Errors keep the existing shape: exit 1, `legu: <message>` on stderr, nothing on stdout. The README gains a Signing section covering the key commands and the signers-list format. Nothing yet reads the signers list on mark; that is the next ticket.

### Blocked by

None (can start immediately).

## Notes

**2026-09-11T19:11:34.993068895Z**

legu key init writes an owner-only seed and key.pub under $XDG_CONFIG_HOME/legu (falling back to $HOME/.config/legu) and refuses a second run; key show prints the signers line; key add creates or appends .review/signers, idempotent, refusing a key bound to another name. Help, completion and --json cover all three; every CLI case runs with XDG_CONFIG_HOME inside its scratch repo.
