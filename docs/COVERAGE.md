# Coverage report

The numbers are not kept here. Print them:

```bash
python3 scripts/coverage.py                # both suites, per file and total
python3 scripts/coverage.py --swift-only
python3 scripts/coverage.py --cli-only
```

This file holds only what those tables do not say.

## The CLI suite adds no line coverage

`--swift-only` and the combined run give the same lines figure, because the
Swift tests call each command's `run()` in process. Do not read that as "the
CLI suite is redundant". Line coverage cannot see what that suite is for:

- the exact bytes on stdout, including a final newline, a lost CR, and a
  trailing space
- the exit code
- what the file holds after `-i`
- how ArgumentParser reads a real command line
- **a crash.** Fixed defect 1 was pinned here because its SIGABRT would have
  taken the Swift test process with it. In the CLI suite it was only an exit
  code, and the case now guards the clean refusal.

Every open defect below sits on a line that coverage already counted.

## The misses are not a backlog

Nearly all of them are unreachable by design: `??` fallbacks whose left side
cannot be nil given the only caller, the `guard let node = node` branches in
`MarkdownParser`, the out of bounds fallback in `calculateRanges`, and the
`sigaction` and `chflags` POSIX failure paths in `InputReader`.

JSON serialization is guarded before Foundation sees the value. This matters
because `JSONSerialization` raises rather than throws for a non-finite number;
checking first keeps those failure paths in Swift and prevents a process abort.

## Two traps in measuring this

Both are handled by `scripts/coverage.py`, and both produced a plausible
looking wrong table before they were found.

**`swift test --enable-code-coverage` exits 1 here even when all tests pass.**
SwiftPM merges the profiles itself and fails the command if any one is
truncated. This package always truncates one on purpose:
`testInPlaceWriteFailureLeavesOriginalUntouched` runs `md` under `ulimit -f 2`,
and the instrumented subprocess hits that limit writing its own profile.

**`swift build` does not build test targets.** Paired with `swift test
--skip-build`, that silently measures whatever test bundle is on disk. It
reported 88.73% where the truth was 98.24%. `--build-tests` fixes it.

## Defects: 24 found, 8 fixed, 16 open

Each open defect is pinned by tests holding the CORRECT expectation, marked as
known failures, so it turns green by itself when it is fixed. **The `known-fail`
file of each case holds the detail: what `md` does today, what it should do, and
the cause.** This is only the index.

Numbers are stable. A fixed defect keeps its number, because commit messages and
`known-fail` files name them.

| # | Defect | Pinned by |
| --- | --- | --- |
| 4 | An HTML block is deleted. No `MarkdownBlock` case | 5 CLI, 1 Swift |
| 6 | Two paragraphs in a blockquote flatten into one run | 1 CLI, 3 Swift |
| 7 | An unused link reference definition is deleted | 3 CLI |
| 11 | A list block absorbs the blank line below it | 2 CLI |
| 12 | `remove`, `replace`, `insert-after` use `parse`, not `parseDocument`, so frontmatter counts as blocks | 4 Swift |
| 13 | An unparseable frontmatter fence reads as no frontmatter, exit 0 | 3 CLI |
| 14 | `list` exits 0 for a missing directory, and for a file | 2 CLI |
| 15 | `--key` on a mapping prints a Swift dictionary description | 1 CLI |
| 17 | `format` rewrites CRLF as LF | 1 CLI |
| 18 | `insert-after` and `replace` invent a final newline | 2 CLI |
| 19 | Untouched blocks are re-spelled: `*`→`-`, `***`→`---`, two trailing spaces→`\` | 2 CLI |
| 20 | An ordered list is renumbered from 1 | 2 CLI |
| 21 | A refusal prints the usage of `md`, not of the subcommand | 4 CLI |
| 22 | `format` has no `-i`. **Do not add it yet** — see below | 1 CLI |
| 23 | `list --key` breaks its one line per file shape on a multi-line value | 1 CLI |
| 24 | `list --output json` pretty-prints an empty array over three lines | 1 CLI |

Fixed: **1** non-finite JSON number abort, **2** soft line break dropped, **3**
hard line break dropped, **5** backslash escapes resolved away, **8** wrapped
list continuation escaped its item, **9** non-ASCII YAML values escaped, **10**
phantom final line counted, **16** null value serialized as `<null>`.

## Two things to know before you fix

**Defect 22 must wait.** Adding `format -i` is one line, but `format` still
loses HTML blocks, link reference definitions, blockquote paragraph breaks,
CRLF endings and list numbering. An in-place flag would write all of that into
the user's file. Fix 4, 6, 7, 17 and 20 first.

**Defect 3 left a residue, and it belongs to 19.** A hard break has two
spellings and both mean the same break. Block text is markdown source, so a
bare newline would have said SOFT where the source said hard; the fix had to
pick a spelling and it writes the backslash, because trailing spaces are
invisible and easy for another tool to strip. A document written with two
spaces therefore comes back with a backslash. `MarkdownBlock` does not remember
which spelling the author used, the same gap that turns `*` into `-`. Fix 19
and this goes with it.

## Where to start

Ordered by tests turned green for code changed:

1. **24**, **14**, **15**, **23** — one command each, and small.
2. **13**, **21** — small, but each touches its callers.
3. **12**, **18**, **19**, **20** together. `insert-before` already does the
   right thing: `parseDocument` plus a splice through `MarkdownSourceEditor`.
   The other three reformat the whole document. That one difference causes all
   four defects.
4. **4**, **7**, **17**, **19**, **20** need `MarkdownBlock` to grow: cases for
   raw HTML and for a link reference definition, and memory of the line ending,
   the bullet character, the break spelling and the list start number. These
   touch every `switch` over the enum.
