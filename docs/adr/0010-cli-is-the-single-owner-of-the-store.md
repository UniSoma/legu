# The CLI is the single owner of the store

Every mutation of `.review/` goes through `legu`; the Emacs package reads
sidecars but never writes one, and `legu-mark` issues exactly one `legu mark`.
A second writer would have to reproduce supersede semantics, path
normalization and the sidecar format, and would drift from the CLI silently.
The cost is 0.3–2.7 s of latency per mark, which the editor hides with an
optimistic paint drawn in an "unverified" style until the CLI confirms.
