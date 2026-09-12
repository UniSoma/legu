# legu

Review coverage for a codebase: which regions of a repository a human has
reviewed, which of those have changed since, and which have never been looked
at. The reading analogue of test coverage.

## Language

### Regions and records

**Region**:
A line range of one file — `(path, start, end)`. The thing you point at when
you mark, and the unit at which review state is tracked.
_Avoid_: range, span, chunk, block

**Opaque region**:
A whole binary or empty file, tracked by its file hash alone. It has no line
range and counts as one line.

**Review record**:
The persisted evidence that a region was reviewed: where it was, at which
commit, what its content looked like, who reviewed it and when. A mark
produces one; anchoring consumes one.
_Avoid_: mark (as a noun), entry, region (for the stored thing)

**Mark**:
To declare a region reviewed as it stands in the working tree right now.
_Avoid_: approve, sign off, check off

**Forget**:
To drop every review record and ticket reference anchored at a region, or
stored against it if its file is gone. Forgetting is the only way state leaves
the store other than a supersede; it says nothing about the code, only that
legu should stop tracking it.
_Avoid_: unmark, delete, clear, reset

**Ticket reference**:
A ticket id anchored to a region. The ticket lives in an issue tracker, which
owns its content and lifecycle; legu owns only the anchor, and re-anchors it
exactly as it re-anchors a review record. Never prose.
_Avoid_: note, annotation, comment, bookmark

### Review state

Every line of an eligible file is in exactly one of the three states.

**Unreviewed**:
The state of a region no human has read.
_Avoid_: untouched, uncovered, unread

**Reviewed**:
The state of a region a human has read and whose content is unchanged since.
_Avoid_: read, audited, checked, seen, covered

**Stale**:
The state of a line a human has read whose content has changed since. Only
the lines a change touched are stale; the rest of the region stays reviewed,
on the evidence of the same review record. A change that leaves the region
no line of its own to point at leaves a seam instead.
_Avoid_: dirty, outdated, invalidated

**Missing**:
A review record whose file no longer exists or cannot be read. It is reported,
counts toward nothing, and is kept until forgotten. Not a state a region can be
in.
_Avoid_: deleted, orphaned

### Anchoring

**Anchoring**:
Locating a review record's content in the working tree and deciding whether it
changed.
_Avoid_: projection, resolution, relocation, tracking

**Same read**:
What two texts are when, after removing the leading whitespace common to every
line of each, they trim equal at the end of each line. Trailing whitespace
never matters and leading whitespace matters relative to the region, so a block
reindented together is the same read as before and a line moved to another
level is not (ADR-0019).
_Avoid_: equivalent, whitespace-insensitive, normalised

**Confirming commit**:
The commit whose text a review record's content hash is checked against before
its diff is trusted: the commit the record cites when that one holds the lines
it signed for, else the first of the few commits after it that does. A mark
made while the working tree was dirty cites a commit whose text it never read,
and the commit that carried the edit into git is where the read is found. A
record no commit confirms, and one made where there is no git, are stale over
their whole region (ADR-0018).
_Avoid_: base commit, matching commit, source commit

**Fragment**:
One of the pieces anchoring reports a review record in when a change landed
inside its region: the lines a hunk wrote, which are stale, or a run of lines
between hunks, which is still reviewed where it now sits. A change reaching
past the region's edge is clipped to the part of it the record read, so a
fragment never covers a line nobody read. Fragmenting is derived at anchoring
time; the record itself stays one signed line for its whole region (ADR-0018).
_Avoid_: part, slice, sub-region, split record

**Seam**:
The one stale line standing for a change that left the region no line of its
own — a deletion, or a change reaching in from outside that shrank below
where the region began in it. It is the line after the change when that line
is still inside the region, and the line before it otherwise, so the seam is
always a line the reader read (ADR-0018).
_Avoid_: gap, join, scar, marker

**Moved**:
A reviewed region whose content is intact but no longer at the recorded
location — shifted by edits above it, cut and pasted within the file, or
carried by a rename. Moved is not stale.
_Avoid_: shifted, relocated, drifted

**Supersede**:
What a mark does to every review record that anchors fully inside the marked
region: retires it. A record that reaches outside the mark is left in place;
the part outside was not re-read.
_Avoid_: overwrite, merge, dedupe

**Ghost**:
A review record that a re-review left behind because it anchored partly
outside the range marked.
_Avoid_: duplicate, stray, orphan

### Coverage

**Eligible file**:
A tracked file not excluded by the store's ignore list. Only lines of eligible
files count.
_Avoid_: in scope, included, countable

**Coverage**:
Three numbers over eligible lines — unreviewed, reviewed, stale — for the
repository, a directory, or one file. Never a single percentage: the stale
count says whether the reader is gaining ground or the codebase is outrunning
them. Where space is short, reviewed and stale are shown and unreviewed is the
remainder.
_Avoid_: progress, completion, score

### Storage

**Store**:
The `.review/` directory at the repo root, committed alongside the code. It
holds everything legu owns: the sidecars under `.review/sidecars/`, the ignore
list at `.review/ignore`, the signers list at `.review/signers`, and a README
written once when the store is created, which is documentation rather than
state and which legu never reads.
_Avoid_: database, index, cache

**Sidecar**:
One file in the store, holding the review records and ticket references of one
source file. The sidecars mirror the source tree under `.review/sidecars/`, one
per file.
_Avoid_: state file, metadata file

### Signing

**Signature**:
The cryptographic proof carried by a review record that its signer produced
it and that no field of it has changed since. Ticket references carry none.
_Avoid_: sign-off, seal, stamp

**Signer**:
The key that produced a signature. A person may sign with several keys; a key
belongs to exactly one reviewer.
_Avoid_: author, identity, owner

**Signers list**:
The committed bindings of signer to reviewer that a store trusts. Its presence
is what makes a store signed: every mark in a signed store must be signed by a
listed signer.
_Avoid_: keyring, allowed signers, trust store

**Signed store**:
A store with a signers list. In a signed store every review record carries a
signature; in an unsigned store none does.
_Avoid_: secure store, verified store

**Verify**:
To check every review record's signature against the signers list and report
the ones that fail. Verification is a report on the store, never a change to
it, and reading commands trust the store without it.
_Avoid_: validate, audit, check

### Reading loop

**Frontier**:
The line a reader is reading from. A mark covers the frontier down to where
the reader is now.
_Avoid_: cursor, bookmark, last position

**Gap**:
The next unreviewed or stale line in a file.
_Avoid_: hole, todo

**Queue**:
What to read next: the files with gaps, in a chosen order — directory order by
default, or by how often each file has changed in the same commit as something
already reviewed.
_Avoid_: reading list, worklist, todo, backlog
