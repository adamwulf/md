# Coverage report

The numbers are not kept here. Print them:

```bash
python3 scripts/coverage.py                # both suites, per file and total
python3 scripts/coverage.py --swift-only
python3 scripts/coverage.py --cli-only
```

This file holds only what those tables do not say.

## The CLI suite adds almost no line coverage

`--swift-only` and the combined run give nearly the same lines figure, because
the Swift tests call each command's `run()` in process. At the latest
measurement, the CLI suite uniquely covers only 3 executable lines and no
function at all. Do not read that as "the CLI suite is redundant". Line
coverage cannot see what that suite is for:

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

The last refusal of `MarkdownSourceEditor` joins them. Every edit that reaches
the re-spelling step is completed by it, so the `return nil` after that loop
has no input that can arrive there. It stays as the floor under a step that
may grow.

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
reported 88.73% where the truth was 98.24%, which were the figures of that
day. `--build-tests` fixes it.

## Defects: 28 found, 23 fixed, 3 open, 2 withdrawn

Each open defect is pinned by tests holding the CORRECT expectation, marked as
known failures, so it turns green by itself when it is fixed. **The `known-fail`
file of each case holds the detail: what `md` does today, what it should do, and
the cause.** This is only the index.

Numbers are stable. A fixed defect keeps its number, because commit messages and
`known-fail` files name them.

| # | Defect | Pinned by |
| --- | --- | --- |
| 21 | A refusal prints the usage of `md`, not of the subcommand | 4 CLI |
| 22 | `format` has no `-i` | 1 CLI |
| 28 | A definition whose label wraps across lines is dropped | 1 CLI |

Fixed: **1** non-finite JSON number abort, **2** soft line break dropped, **3**
hard line break dropped, **4** HTML blocks deleted, **5** backslash escapes
resolved away, **6** two
blockquote paragraphs flattened into one run, **7** link reference definitions
deleted, at the top level and inside list items, **9** non-ASCII
YAML values escaped, **10** phantom final line counted, **11** a list block
absorbed the blank line below it, **12** editing commands
counted frontmatter as blocks, **13** malformed frontmatter read as empty,
**14** `list` reported success for invalid paths, **15** `--key` mapping printed
as a Swift dictionary, **16** null value serialized as `<null>`, **18** editing
commands invented a final newline, **19** editing commands re-spelled untouched
blocks, **20** ordered lists renumbered from one, **23** `list --key` split one
file across multiple lines, **24** empty JSON arrays spanned three lines,
**25** an edit destroyed the code block below it, **26** a code fence was closed
by the backticks it enclosed, **27** a used link reference resolved inline while
its definition was dropped.

Withdrawn: **8** expected a list continuation to be a separate block, but the
continuation belongs to the item and formatting is idempotent. **17** expected
`format` to preserve CRLF, but LF is the intentional canonical line ending for
this project.

## A fence is not a re-spelling the editor chose freely

Defects 25 and 26 are worth reading together, because 25 broke the rule that
defect 19 established and it had to.

**25.** Blank lines do not end a list, and a line indented as far as the item
content continues that item. A top-level indented code block therefore cannot
sit directly below a list: **no document can hold that shape**. The case that
pinned 25 expected exactly that shape, so the expectation was impossible, and
the bytes it asked for were the corruption. Reading them back gives one list,
with the code block turned into a paragraph of the last item.

Only three things close a list there, and each writes something the author did
not: an HTML block, a thematic break, or text at column 0. The fourth way out
is to re-spell the code block itself, and that is what the editor does. It is
the last step it tries, after every byte-preserving candidate has failed, so
defect 19's promise still holds everywhere it can: an untouched block keeps its
own bullet, its own break spelling, and its own bytes. Only the block that the
edit would otherwise destroy is re-spelled, and only into the fenced form that
`md format` already writes for every code block.

**26** was found on the way. `BlockFormatter` wrote a fixed three-backtick
fence, so code holding a line of three backticks closed its own fence. The
fence is now one longer than the longest run it encloses. Without that, the
fix for 25 would have carried the defect into `remove` and `replace`.

## Two things to know before you fix

**Defect 22 is unblocked.** It had to wait while `format` lost link reference
definitions, because an in-place flag would have written that loss into the
user's file. Defects 7 and 27 are fixed, so `format -i` can now be added
safely.

**Defect 3 has an intentional canonical spelling.** A hard break has two
spellings and both mean the same break. `format` writes the backslash because
trailing spaces are invisible and easy for another tool to strip. Defect 19
was that an editing command also re-spelled blocks the user did not name. Those
commands now splice the original source, so an untouched two-space hard break,
asterisk bullet, or thematic break remains byte-for-byte unchanged.

## Where to start

Ordered by tests turned green for code changed:

1. **21** is small, but touches each editing command.
2. **22** is one flag on `format`, unblocked now that 7 and 27 no longer
   lose link reference definitions.
