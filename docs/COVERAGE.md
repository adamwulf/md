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
the Swift tests call each command's `run()` in process. The CLI suite holds 4
lines of 3180 alone, and no function at all. Do not read that as "the CLI
suite is redundant". Line coverage cannot see what that suite is for:

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

## Defects: 26 found, 13 fixed, 12 open, 1 withdrawn

Each open defect is pinned by tests holding the CORRECT expectation, marked as
known failures, so it turns green by itself when it is fixed. **The `known-fail`
file of each case holds the detail: what `md` does today, what it should do, and
the cause.** This is only the index.

Numbers are stable. A fixed defect keeps its number, because commit messages and
`known-fail` files name them.

| # | Defect | Pinned by |
| --- | --- | --- |
| 4 | An HTML block is deleted. No `MarkdownBlock` case | 6 CLI, 1 Swift |
| 6 | Two paragraphs in a blockquote flatten into one run | 1 CLI, 3 Swift |
| 7 | An unused link reference definition is deleted | 3 CLI |
| 11 | A list block absorbs the blank line below it | 2 CLI |
| 13 | An unparseable frontmatter fence reads as no frontmatter, exit 0 | 3 CLI |
| 14 | `list` exits 0 for a missing directory, and for a file | 2 CLI |
| 17 | `format` rewrites CRLF as LF | 1 CLI |
| 20 | An ordered list is renumbered from 1 | 2 CLI |
| 21 | A refusal prints the usage of `md`, not of the subcommand | 4 CLI |
| 22 | `format` has no `-i`. **Do not add it yet** — see below | 1 CLI |
| 23 | `list --key` breaks its one line per file shape on a multi-line value | 1 CLI |
| 24 | `list --output json` pretty-prints an empty array over three lines | 1 CLI |

Fixed: **1** non-finite JSON number abort, **2** soft line break dropped, **3**
hard line break dropped, **5** backslash escapes resolved away, **9** non-ASCII
YAML values escaped, **10** phantom final line counted, **12** editing commands
counted frontmatter as blocks, **15** `--key` mapping printed as a Swift
dictionary, **16** null value serialized as `<null>`, **18** editing commands
invented a final newline, **19** editing commands re-spelled untouched blocks,
**25** an edit destroyed the code block below it, **26** a code fence was
closed by the backticks it enclosed.

Withdrawn: **8** was an incorrect expectation, not a formatter defect. The
continuation is indented beneath the list item's content and formatting the
result again is idempotent, so it remains part of the same item.

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

**Defect 22 must wait.** Adding `format -i` is one line, but `format` still
loses HTML blocks, link reference definitions, blockquote paragraph breaks,
CRLF endings and list numbering. An in-place flag would write all of that into
the user's file. Fix 4, 6, 7, 17 and 20 first.

**Defect 3 has an intentional canonical spelling.** A hard break has two
spellings and both mean the same break. `format` writes the backslash because
trailing spaces are invisible and easy for another tool to strip. Defect 19
was that an editing command also re-spelled blocks the user did not name. Those
commands now splice the original source, so an untouched two-space hard break,
asterisk bullet, or thematic break remains byte-for-byte unchanged.

## Where to start

Ordered by tests turned green for code changed:

1. **24**, **14**, **23** — all three in `ListCommand.swift`, in three
   different functions, and none of them touches the parser or the shared
   block model. 4 markers for one file. See the section below.
2. **13**, **21** — small, but each touches its callers.
3. **11**, **6** — localized parser range and container-separator fixes.
4. **4**, **7**, **17**, **20** need the parsed document model to grow: cases
   for raw HTML and link reference definitions, plus memory of the line ending
   and ordered-list start number. These touch every `switch` over the enum.
   Take **4** first of the four. `<!-- -->` is the CommonMark idiom for
   holding two blocks apart, and deleting it does not only lose the comment:
   `format-keeps-an-html-comment-that-separates-two-lists` shows two lists
   merging into one, which moves every block index below that point.
5. **22** only after **4**, **6**, **7**, **17**, and **20**, so in-place
   formatting cannot write any of those losses into the user's file.

## The three `list` defects, read but not yet fixed

Each `known-fail` file says what `md` does and why. This is what reading the
source added, so the next session does not read it again.

**14 has a mechanism waiting for it.** `run()` already ends with

    if prepared.hadErrors { throw ExitCode.failure }

and `prepareEntriesForRendering` already sets that flag for a file it had to
skip. So `list` knows how to walk everything and then exit non-zero, which is
the behaviour wanted here. What is missing is only the report: `walkDirectory`
writes to stderr and returns `[]`, and `collectEntries` returns a plain array,
so nothing reaches `run()`. Give both of them a way to carry the flag that
already exists. Do not add a second exit path.

**24 is one branch.** `renderJSON` hands the array straight to
`JSONSerialization` with `.prettyPrinted`, and Foundation writes `[\n\n]` for
an empty array. Answer `[]` before that call. Note that `render` appends the
final newline itself, so the branch returns `[]` and nothing more.

**23 must not lose the tab shape.** The `--key` branch of `renderPlain` writes
`"\(entry.path)\t\(formatted)\n"`, and `formatScalarValue` ends at
`"\(normalized)"` for a scalar: no quoting, no escaping, no test for a
newline. Escaping the newline as `\n` is the smallest fix. The case asserts
`md lines --count` is 1, so any fix that keeps one record on one line closes
it. `formatScalarValue` also serves arrays and mappings through
`serializeInlineCollection`, thus check where the escape belongs before you
write it: a newline inside a mapping value has the same problem.
