# Anchor by diff-hunk shifting plus a content hash, not `git log -L` or `git blame`

To decide whether a reviewed region is still current, legu diffs the file as it
was at the reviewed commit against the working tree (`git diff --no-index
-U0`), shifts the region across the hunks above it, and compares a hash of the
region's normalized content. The original requirements recommended `git log
-L` (accurate, slow on years of history) or `git blame -M -C` (fast, coarse).
Both answer a proxy question — which commit last touched these lines — while
the hash answers the real one: did the content change. Diff shifting is also
faster than either, and works with no git at all by falling back to the hash.

## Considered options

- `git log -L <start>,<end>:<path>` between the reviewed SHA and HEAD: exact
  line tracking, but a full history walk per region.
- `git blame -M -C`: one call per file, but reports a touch as a change even
  when the content is identical, and cannot confirm what was actually read.
