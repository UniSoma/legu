# Review state is measured against the working tree, not HEAD

`stale`, `status` and `coverage` compare records with the files on disk, so an
uncommitted edit inside a reviewed region shows up as stale immediately.
Comparing against HEAD would be cheaper and stable across an editing session,
but the reader is looking at the working tree, and a gutter that calls a
region reviewed while its content is different from what was read is a lie.
