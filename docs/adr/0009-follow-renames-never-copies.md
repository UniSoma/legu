# A mark follows a git rename, never a copy

When a reviewed file is gone from its recorded path, legu looks for it where
git reports a rename (at a low similarity threshold, so a small file that was
renamed and edited is still matched), and only when the original is gone,
among files added since that contain the reviewed block. It never follows a
copy. If a copy could absorb a mark, then copying a file and editing the
original inside a reviewed region would leave the copy counted as reviewed and
hide a real change. The cost is that a rename which also leaves a new,
unrelated file at the old path reports stale rather than following the move —
conservative in the direction that asks for a re-read.
