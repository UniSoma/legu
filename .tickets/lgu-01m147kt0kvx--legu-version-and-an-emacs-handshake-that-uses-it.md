---
id: lgu-01m147kt0kvx
title: legu --version, and an Emacs handshake that uses it
status: open
type: feature
priority: 3
mode: afk
created: '2026-08-28T13:05:43.955151886Z'
updated: '2026-08-28T13:05:43.955151886Z'
acceptance:
- title: '`legu --version` and `legu --version --json` both exit 0 and report the version and the store schema'
  done: false
- title: The version is defined in one place in the script, not repeated
  done: false
- title: The Emacs package checks the version on first use and says something useful when it does not recognise it
  done: false
- title: The Emacs `--help` text canary is replaced by the version check
  done: false
---

## Description

There is no version handshake at all. `legu --version` exits 1 with
`unknown option: --version`, so a client has nothing to check against.

The Emacs package works around this by probing `--help` and asserting the usage
text still names all seven commands — a canary that only fires once the surface
has already moved under it, and one that a harmless wording change trips.

    $ legu --version
    legu 0.4.1 (store schema 1)

    $ legu --version --json
    {"version": "0.4.1", "schema": 1}

`schema` is the sidecar schema the binary writes, which is what a client
actually needs to know before trusting what it reads out of `.review/`.
