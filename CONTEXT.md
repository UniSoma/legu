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
The state of a region a human has read whose content has changed since. Any
change inside the region makes the whole region stale.
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

**Moved**:
A reviewed region whose content is intact but no longer at the recorded
location — shifted by edits above it, cut and pasted within the file, or
carried by a rename. Moved is not stale.
_Avoid_: shifted, relocated, drifted

**Supersede**:
What a mark does to every record that anchors to exactly the same place:
replaces it.
_Avoid_: overwrite, merge, dedupe

**Ghost**:
A review record that a re-review left behind because it anchored to a
slightly different range from the one marked.
_Avoid_: duplicate, stray, orphan

### Coverage

**Eligible file**:
A tracked file not excluded by `.reviewignore`. Only lines of eligible files
count.
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
The `.review/` directory at the repo root, committed alongside the code.
_Avoid_: database, index, cache

**Sidecar**:
One file in the store, holding the review records and ticket references of one
source file. The store mirrors the source tree, one sidecar per file.
_Avoid_: state file, metadata file

### Reading loop

**Frontier**:
The line a reader is reading from. A mark covers the frontier down to where
the reader is now.
_Avoid_: cursor, bookmark, last position

**Gap**:
The next unreviewed or stale line in a file.
_Avoid_: hole, todo

**Queue**:
What to read next: the files with gaps, in directory order.
_Avoid_: reading list, worklist, todo, backlog
