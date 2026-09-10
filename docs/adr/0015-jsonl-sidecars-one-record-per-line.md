# Sidecars are JSON Lines, one record per line

Under ADR-0014 a review record spans four to six lines of EDN, so every mark,
supersede or forget shows up in a pull request as that many changed lines, and
in a review-heavy commit the store's diff outweighs the code's. A sidecar is
now schema 3 at `.review/<path>.jsonl`: a header line `{"schema":3}`, then
every review record on one line sorted by region, then every ticket reference
sorted the same way. Adding, superseding or forgetting a record changes one
line. The line is rendered by hand in a fixed key order with no whitespace and
hyphenated keys: region first, then reviewer or ticket with the timestamp,
then commit, file hash and content hash, so what a human scans sits in the
first sixty columns and the hashes are a tail the eye skips. Hashes stay full
and hex, as ADR-0014 decided; timestamps are whole seconds. A line with a
`reviewer` is a review record and a line with a `ticket` is a ticket
reference, exactly as CONTEXT.md defines them, with no kind field to disagree.
The CLI parses per line with cheshire and the Emacs package with its native
JSON parser; a line that does not parse makes the whole sidecar unreadable, so
a half-merged sidecar is refused as before. A committed `.gitattributes` marks
`.review/**` as generated, which collapses sidecars in GitHub and GitLab
review views. Two consequences were measured after the choice, not the reason
for it: parsing 10,000 sidecars of 20 records takes 0.75 s against 2.37 s for
the EDN layout in babashka, and the hand-written EDN reader in `legu.el` goes
away. Schema 2 is refused, not migrated: no store existed outside this
repository when the format changed. Supersedes ADR-0007. ADR-0014's ordering
and merge arguments stand; its layout does not.

## Considered options

- Stay on EDN and ship a `textconv` diff driver that renders a record in a
  humane form: changes how a changed line looks, not how many lines change,
  and needs `git config` in every clone.
- A `kind` field on every line: a second source of truth that can disagree
  with the keys the glossary already defines a record by.
- The schema in every record, or in a store-level file: the first bloats every
  line, the second makes a sidecar meaningless on its own.
- base64url hashes, 43 characters instead of 64: same bits, but `sha256sum`
  and `git hash-object` print hex, and the width buys nothing once the hashes
  are the tail of the line.
- Skip lines that fail to parse: reads around a merge conflict by dropping the
  records inside it, and a write over that file would lose them for good.
