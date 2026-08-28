# The editor may confirm "reviewed, in place" locally; it may never pronounce stale, moved or missing

Opening a file in Emacs reads its sidecar and hashes the file, with no
subprocess. A record whose stored file hash still matches is exactly the case
the CLI's own anchoring answers immediately, so the editor may paint it
reviewed at the stored range. A record whose hash differs is painted as
nothing and a `legu status`/`legu stale` snapshot is requested; the editor
does not run the diff-shifting ladder itself. Two reasons: a local content-hash
match confirms state but not range (the CLI checks the hash at the range
projected through diff hunks, so painting at the stored range would be off by
the hunk offset), and any reimplementation of anchoring is a second set of
semantics that drifts. A snapshot may only pronounce on a file it is newer
than; otherwise an edit-then-save inside a reviewed region would still be
painted reviewed by a stale snapshot.
