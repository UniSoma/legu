# `legu note` becomes `legu ticket`, and prose annotations are rejected again

The command that anchors a ticket id to a region was called `note`, and its
own author read it as "attach a text comment". The name lied about what it
stores. It is renamed to `legu ticket <region> <id>`, the sidecar vector from
`:notes` to `:tickets`, and the Emacs commands to match. A separate short
free-text comment was considered and rejected for the reasons in ADR-0008:
prose in sidecars reintroduces the merge conflicts the per-file layout exists
to avoid, wants editing and searching that legu will never do as well as a
tracker, and has no lifecycle so it rots. A one-line remark is a `chore`
ticket. The vestigial `:notes` field on review records — never written, only
carried across a supersede — is removed with the rename; ticket references are
independent anchors and survive a re-mark on their own.

## Considered options

- Keep `note` and document that it takes an id: the glossary would be fighting
  the verb forever.
- Add a comment field alongside the ticket reference: the second issue tracker
  ADR-0008 warned about.
