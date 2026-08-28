# Review Coverage Tool — Requirements

Handoff document. Written to be pasted into a fresh session as full context.

## 1. Problem

A hypotetical codebase — thousands of commits, two years of history — needs to be
read and understood in full by a human. The goal is **100% human review
coverage**: the reading analogue of test coverage.

Reading a codebase this size takes weeks or months. During that time the code
keeps changing. Without tooling there is no way to know what has been read, what
has been read but has since changed, and what has never been looked at.

## 2. Goals

1. Track review state at sub-file granularity, persistently, across sessions.
2. Attach free-form notes to code regions without modifying the source.
3. Automatically invalidate review state when the underlying code changes.
4. Report coverage: what fraction of the codebase is read, stale, or untouched.

## 3. Non-goals

- **No language-specific behaviour.** No parsers, no per-language plugins, no
  syntactic units (function, class, namespace). The tool must work identically
  on Clojure, YAML, shell scripts, and SQL migrations.
- **Not a code review tool.** No PR workflow, no approvals, no diff UI.
- **Not an issue tracker.** See §7.
- **No reading-order recommendations.** Dependency analysis is language-specific
  and out of scope.

## 4. Core concepts

**Region** — the unit of review state: `(path, start_line, end_line)`. Lines are
the only structural unit available without parsing. Non-text files (binaries,
images) are treated as a single opaque region with no line range.

**Review state** — every region is in exactly one of:

- `unreviewed` — never read
- `reviewed` — read, and the content is unchanged since it was read
- `stale` — read, but the content has since changed; needs re-reading

**Review record** — what gets persisted when a region is marked reviewed:

| Field | Purpose |
|---|---|
| `path` | file path at review time |
| `start_line`, `end_line` | line range at review time |
| `commit` | SHA of HEAD at review time |
| `content_hash` | hash of the region's normalized content |
| `reviewer`, `timestamp` | provenance |
| `notes` | references to external notes (§7), not prose |

## 5. Anchoring and staleness

This is the hard part. A review mark records a line range at a point in history;
the tool must project that range onto the current HEAD and decide whether the
content changed. Two mechanisms, used together:

### 5.1 Git for projection

`git log -L <start>,<end>:<path>` follows a line range backward through history
across edits, moves, and renames. It is git's own line-range tracking and is
completely content-agnostic. Running it between the reviewed SHA and HEAD yields
both the region's current location and whether anything touched it.

`git blame -M -C` is the cheaper approximation: for each current line, find the
commit that last changed it. If that commit is not an ancestor of the reviewed
SHA, the line is stale. Faster, coarser, adequate for a first implementation.

This gives rename-following, move detection, and staleness from one mechanism
with zero knowledge of file contents.

### 5.2 Content hash for verification

Store a hash of the region's content at review time. It does not locate
anything — it confirms that what git projected forward is what was actually
read. It is also the fallback if the project is not in git.

**Normalization:** strip leading and trailing whitespace per line before
hashing. Whitespace is near-universal across text formats; anything more
aggressive (ignoring comments, normalizing tokens) reintroduces language
assumptions and is forbidden.

### 5.3 Fallback ladder

Adopt SonarQube's issue-matching approach, which solves the same problem for
static-analysis findings:

1. Detect file renames first.
2. Strongest match: same line number **and** same content hash.
3. Fallback: detect block moves within the file, match on the moved line.
4. Weaker heuristics after that.

Also worth reviewing: SARIF `partialFingerprints`, which standardizes this idea
for tool interchange.

### 5.4 Staleness granularity

Whole-region: if any line in a reviewed region changed, the entire region goes
stale. Simpler and more honest — a small change can invalidate understanding of
the whole. The cost is that large regions go stale constantly. Mitigation is
guidance, not code: mark regions roughly the size you can hold in your head at
once.

A region that merely *moved* (shifted because something above it changed) is
**not** stale. Only changed content is.

## 6. Storage

- A sidecar directory at the repo root: `.review/`, committed alongside the code.
- **One file per source file**, mirroring the source tree. A single index file is
  simpler but will conflict constantly if more than one person reviews.
- Format: EDN or JSON. Human-readable and diffable is a hard requirement.
- Source files are never modified.

## 7. Notes / sidecar comments

The user needs to record observations while reading — things to investigate,
refactor, or question later — without touching the source.

**These are tickets, not annotations.** They have state, they get closed, they
reference each other. There is an existing CLI ticket tracker project (working
names: `knot` / `tix`) that already handles dependency tracking, cycle
detection, and partial ID matching.

**Split the responsibility:**

- This tool owns *review coverage state* and emits anchored region references.
- The ticket tracker owns *note content and lifecycle*.
- A review record holds a ticket ID, not prose.

Otherwise this grows a second issue tracker inside itself within a month.

The anchoring machinery in §5 should be reusable so that ticket references to
code regions also survive edits and go stale.

## 8. Coverage reporting

Metric: `reviewed_lines / eligible_lines`.

Eligibility is defined by a `.reviewignore` file using gitignore syntax —
vendored code, generated files, lockfiles, fixtures. Gitignore syntax because
users already know it.

Report **three** numbers, never one:

- never read
- reviewed and current
- reviewed but stale

The third is the interesting one: it says whether the reader is gaining ground
or the codebase is outrunning them.

Also useful: a "what to read next" query that surfaces unreviewed and stale
regions, ordered by directory or by commit co-change frequency (both generic).

## 9. Interface

CLI first. Roughly:

```
legu mark <path>[:<start>-<end>]    # mark region reviewed at HEAD
legu status [<path>]                # state of a file or tree
legu stale                          # list regions needing re-read
legu next                           # suggest what to read next
legu coverage                       # the three numbers
legu note <path>:<range> <ticket-id>  # attach a ticket reference
```

Editor integration is a later concern. If it happens, the sidecar format must
already support it — which the per-file design does.

## 10. Prior art

Nothing found combines all four goals. Every existing tool does a subset.

**weAudit** (Trail of Bits, VSCode) — closest overall. Marks whole files and
partial regions as reviewed, bookmarks regions for findings and notes, shares
state between auditors, logs LOC audited per day. No evidence of staleness
tracking, which fits its origin: a security audit is a point-in-time engagement
against a frozen commit. **Read its state file format before designing ours.**
`github.com/trailofbits/vscode-weaudit`

**Code Review Progress Tracker** — thin VSCode extension, marks sections
OK/Warning/Danger with persistence. No git awareness.
`github.com/narbonnais/Code-Review-Progress-Tracker`

**SciTools Understand Annotations** — annotations bound to code *entities*
(files, classes, functions), stored outside source, shared via git, anchored by
parsing. The syntactic-anchoring path we are deliberately not taking. Their own
docs admit line-level anchoring is their weaker mode.

**annotate.el** (Emacs) — annotations on arbitrary files without modifying them,
stored in a separate DB. Fully generic; storage is user-level rather than
per-repo.

**anno** (`github.com/jryans/anno`) — annotation aggregation with pluggable
"producer" commands rendering a git-annotate-style gutter. Good architectural
model if review state, blame, and coverage should share one view.

**git notes** — alternative storage backend; attaches machine-readable metadata
to git objects without changing their SHAs. Weirder sync story than a directory.

**SonarQube issue matching** — the anchoring algorithm to copy (§5.3).

**Reviewable** — has the staleness semantics (see only what changed since you
last looked, even after rebase; comments map across changes) but scoped to pull
requests, not the whole tree, and hosted.

**git-code-review** (`github.com/mackuba/git-code-review`) — same idea at commit
granularity; stores state in `.git/review`.

## 11. Open decisions

1. **`git log -L` vs `git blame`** for projection. `-L` is accurate but slow on a
   two-year history; blame is fast and coarse. Benchmark on the real repo before
   committing.
2. **Region size guidance** — needs a real answer once there is usage data.
3. **Multi-branch semantics** — is review state per-branch or global? Global is
   simpler; per-branch is more correct and probably not worth it.
4. **Partial staleness** — deferred, but revisit if whole-region invalidation
   proves too noisy in practice.
