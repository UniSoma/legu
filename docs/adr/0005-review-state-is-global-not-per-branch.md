# Review state is global, not per-branch

One store, whatever branch is checked out. Per-branch state would be more
"correct" but anchoring re-derives everything from content and the working
tree, so a region reviewed on one branch is recognized as reviewed on any
branch where its content is intact, and stale wherever it differs. Per-branch
state would add a dimension to every record and every query for a case the
content hash already handles.
