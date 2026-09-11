# Review records are signed with a per-user Ed25519 key, opt-in per store

A review record's `reviewer` was free text from `git config user.name` or
`--reviewer`, so anyone with push access could write a line saying a colleague
reviewed a region, or edit the region and hashes of a genuine record, and
nothing would tell. A review record in a signed store now carries an Ed25519
signature over its own canonical line, the bytes ADR-0015 already renders in a
fixed order, without the `signature` key and prefixed with a fixed domain
string so the key can never be made to sign anything but a legu record. The
signature is 64 raw bytes, base64, the last key on the line, so a mark is
still a one-line diff. The key is legu's own, not git's: babashka ships the
JDK's Ed25519, so generation, signing and verification are function calls with
no external tool, and `verify` over thousands of records costs nothing;
`ssh-keygen -Y` or `gpg` would be the first runtime dependency beyond git, a
process spawn per record, and unable to read a passphrase-protected OpenSSH
key from babashka at all. The private key lives per user at
`$XDG_CONFIG_HOME/legu/key`, mode 0600, without a passphrase: a prompt on
every mark would break the reading loop, and the Emacs `legu-mark` has no
terminal to prompt on. The trust root is a committed `.review/signers`, one
`<public key> <reviewer name>` line per key, a key bound to exactly one name,
a name free to own several keys. Its presence is the switch: without it a
store behaves as before, with it every mark must be signed by a listed key and
the reviewer name is taken from that line, so `--reviewer` is an error in a
signed store rather than a record that fails the moment it is written.
`legu key init` generates the key, `legu key show` prints the public line,
and `legu key add` appends it to the current repo's signers list, turning
signing on for the repo as a deliberate commit. `legu verify` reports, per
record: valid, bad signature, signer not listed, name differs from the one
the signers list gives that key, or unsigned in a signed store, and exits
non-zero if any record is not valid; `status`, `stale` and `next` trust the
store and do not verify. Forget and supersede are unchanged: a signature
proves origin, not permanence, and removal is a one-line deletion git shows.
Ticket references are pointers, not claims by a person, and stay unsigned.
The record shape changes, so the sidecar is schema 4 and schema 3 is refused,
not migrated, as with every schema before it. What this does not defend:
someone with push access can still add their own key under another's name,
but that is a diff to one committed file, reviewable and blameable, the same
limit git's `allowed_signers` has; and no signature says the reviewer read the
region, only that they marked it.

## Considered options

- Reuse the git signing key through `ssh-keygen -Y` or `gpg`: no new identity
  to vouch for, but an external dependency, a spawn per verification, and
  encrypted SSH keys unreadable from babashka.
- Sign only the reviewer name: cheaper to reason about, but the region,
  timestamp and hashes could then be edited under a valid signature.
- A detached signature file per sidecar or per record: keeps record lines
  short at the cost of twice the files and a merge that can leave a record and
  its signature out of step.
- Always on, no signers switch: one code path fewer, but a solo reader trying
  legu on a scratch repo would need a key before the first mark.
- Verify on every read, an invalid record counting as unreviewed: a bad
  signature is a fact about the store, not the code, and belongs in a report
  that names the record and the reason, as missing records are reported today.
