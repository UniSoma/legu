# Coding standards

What a review checks a diff against. `bb lint` already enforces clj-kondo and
prose width; everything here is for the reviewer.

## Words

Code, tests, help text, messages, comments and docs use the glossary's words
in [CONTEXT.md](CONTEXT.md), and each entry's _Avoid_ list binds. The ones
changes slip on most:

- **mark** is the act. The stored thing is a **review record**.
- **verify** is what `legu verify` does; _check_ is on its _Avoid_ list.
- A **signer** is a key. A key paired with a reviewer name in the signers list
  is a **binding**.

A new concept takes its word from CONTEXT.md, or adds one there in the same
change.

## Prose

- The README, the Emacs README and CONTEXT.md wrap at about 78 columns. An edit
  that lengthens a line rewraps its paragraph.
- Plain sentences that say something the code beside them does not.

## Comments and docstrings

- A comment says why: the constraint, the gotcha, the decision, citing its ADR.
  A sentence that restates the code below it goes.
- A fact is stated once, next to the code that depends on it.

## The script

- Errors go through `die`: exit 1, `legu: <message>` on stderr, nothing on
  stdout. A message names the next command to run when there is one.
- Output goes through `emit`, so every `--json` has kebab-case keys.
- A command or option joins the command table, and parsing, help and
  completion follow from it.
- A command that fails leaves the store as it was: every check that can refuse
  runs before the first write.

## Tests

- The CLI suite drives the real script from a scratch repo and asserts on exit
  code, stdout and stderr.
- Every case keeps `XDG_CONFIG_HOME`, and `HOME` when it reaches for the home
  directory, inside its scratch repo.
- A refusal is asserted with `fails-with`, which also checks the store is
  unchanged.
- A shape repeated across cases becomes a helper, defined before its first use.
- ERT cases are named `legu-test-<sentence>`; the integration half runs inside
  `legu-test--with-repo`. The Emacs README's test count follows the suite.

## Commits

An imperative subject with no ticket id and no trailing period. A body of
plain paragraphs saying why, naming ADRs and tickets, and what the tests pin.
Ticket bookkeeping is a separate "Point <id> at its commit" commit.
