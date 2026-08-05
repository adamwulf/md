# Coverage report

A snapshot, measured 2026-08-04. Regenerate it at any time:

```bash
python3 scripts/coverage.py                # the combined table below
python3 scripts/coverage.py --swift-only
python3 scripts/coverage.py --cli-only
```

Suite sizes at the time of measuring: 750 Swift tests, 429 CLI cases.

## Headline

Coverage of `Sources/` only. Test code and checked out dependencies are
excluded, because their coverage says nothing about this package.

| Measured by | Lines | Functions | Regions |
| --- | --- | --- | --- |
| `swift test` | 98.34% | 94.89% | 95.27% |
| `cli-tests` | 89.69% | 84.31% | 82.86% |
| Both together | **98.34%** | **94.89%** | **95.36%** |

Up from 80.84% / 73.36% / 71.29% at the start of this work.

## Read the third row carefully

**The CLI suite adds no line coverage, and one region.** Almost every line
it reaches, a Swift test reaches too, because the Swift tests call each
command's `run()` in process rather than testing only the helper types
around it. The lines column is the same in row one and row three, and the
regions column moves by 0.09 points.

That is the honest result, and it is easy to draw the wrong conclusion from
it. It does not mean the CLI suite is redundant. It means line coverage
cannot see what that suite is for:

- the exact bytes on stdout, including a final newline, a lost CR, and a
  trailing space
- the exit code
- what the file holds after `-i`
- how ArgumentParser reads a real command line
- **a crash.** `md format --frontmatter json` aborts with SIGABRT on a
  frontmatter value of `.nan`. No Swift test can assert that, because the
  abort takes the test process with it. In the CLI suite it is only an exit
  code, and two cases pin it.

A line can be covered and still be wrong. Of the 21 open defects listed
below, every one sits on a line that coverage already counted as covered.

So do not read these numbers as "the CLI suite has enough cases". Read
`--swift-only` against `--cli-only` for the thing they do tell you: which
lines rest on one suite alone.

## Per file, both suites together

| File | Lines | Functions | Regions |
| --- | --- | --- | --- |
| `MarkdownKit/MarkdownEscaper.swift` | 99.47% | 100.00% | 93.64% |
| `MarkdownKit/MarkdownParser.swift` | 98.10% | 97.14% | 92.02% |
| `md/BlockFormatter.swift` | 100.00% | 100.00% | 100.00% |
| `md/Commands/BlocksCommand.swift` | 98.53% | 87.50% | 97.14% |
| `md/Commands/FormatCommand.swift` | 95.65% | 100.00% | 94.44% |
| `md/Commands/FrontmatterCommand.swift` | 100.00% | 100.00% | 98.51% |
| `md/Commands/InsertAfterCommand.swift` | 100.00% | 100.00% | 100.00% |
| `md/Commands/InsertBeforeCommand.swift` | 97.83% | 100.00% | 95.24% |
| `md/Commands/LinesCommand.swift` | 100.00% | 100.00% | 100.00% |
| `md/Commands/ListCommand.swift` | 97.59% | 92.11% | 94.89% |
| `md/Commands/RemoveCommand.swift` | 100.00% | 100.00% | 100.00% |
| `md/Commands/ReplaceCommand.swift` | 100.00% | 100.00% | 100.00% |
| `md/Commands/TocCommand.swift` | 100.00% | 100.00% | 100.00% |
| `md/Frontmatter.swift` | 96.89% | 83.33% | 94.36% |
| `md/InputOptions.swift` | 100.00% | 100.00% | 100.00% |
| `md/InputReader.swift` | 97.13% | 96.00% | 90.22% |
| `md/MarkdownDocumentParser.swift` | 100.00% | 100.00% | 100.00% |
| `md/MarkdownSourceEditor.swift` | 100.00% | 100.00% | 97.73% |
| **TOTAL** | **98.34%** | **94.89%** | **95.36%** |

## What the remaining 1.66% is

Not a backlog. Nearly all of it is unreachable by design:

- `??` fallbacks whose left side cannot be nil given the only caller
- the `guard let node = node` nil branches in `MarkdownParser`
- the out of bounds fallback in `calculateRanges`
- the `sigaction` and `chflags` POSIX failure paths in `InputReader`

Two misses are different, and are worth knowing about. The
"serialization failed, fall through" branch at `FormatCommand.swift:75` and
the `catch` at `ListCommand.swift:226` are **dead code today**: the only
realistic failure is the non-finite number below, and it aborts the process
before either can run. Fix defect 1 and both branches become reachable.

## Defects: 24 found, 3 fixed, 21 open

Every open defect is pinned by a test that holds the CORRECT expectation and
is marked as a known failure, so each one turns green by itself when it is
fixed.

- 43 CLI cases carry a `known-fail` file saying what `md` does today, what it
  should do, and what was worked out about the cause.
- 11 `XCTExpectFailure` assertions do the same on the Swift side.

If a marked case starts passing, both suites report it loudly rather than
going quiet. Delete the marker then.

The numbers below are stable. A fixed defect keeps its number and moves to
the table at the end, so that a commit message or a `known-fail` file that
names a number still names the same thing.

### Crash

| # | Defect | Pinned by |
| --- | --- | --- |
| 1 | `.nan` or `.inf` in frontmatter reaches `JSONSerialization`, which RAISES rather than throws. `md format --frontmatter json` and `md list --format json` abort with SIGABRT. In `list` one bad file takes down a whole directory walk. | 2 CLI, 2 Swift |

### Data loss

| # | Defect | Pinned by |
| --- | --- | --- |
| 4 | An HTML block is deleted outright. It has no `MarkdownBlock` case. | 5 CLI, 1 Swift |
| 6 | Two paragraphs in a blockquote are flattened into one run. | 1 CLI, 3 Swift |
| 7 | An unused link reference definition is deleted. | 3 CLI |
| 8 | A list item wrapping to a second source line reformats so the continuation escapes the item. Formatting twice changes the document structure. | 1 Swift |
| 9 | `--set` on any key rewrites every non-ASCII value as an escape: `Café` becomes `"Caf\xE9"`. `Yams.dump` is called without `allowUnicode`. With `-i` the escaped bytes land in the user's file. | 3 CLI |

### Wrong answers

| # | Defect | Pinned by |
| --- | --- | --- |
| 10 | `lines` counts one line too many. `components(separatedBy: "\n")` leaves an empty element after the final newline. A 3 line file reports 4, an empty file reports 1, and `lines 4` on a 3 line file exits 0 and prints a blank line instead of refusing. | 5 CLI |
| 11 | A list block absorbs the blank line below it. A list on lines 3-4 is reported as L3-5, and the printed slice carries the blank line. No other block type does this. | 2 CLI |
| 12 | `remove`, `replace` and `insert-after` call `MarkdownParser.parse` instead of `parseDocument`, so YAML frontmatter counts as 2 extra blocks. `md blocks` and `md remove` disagree about the numbering, and an edit can rewrite the frontmatter as `---\n\n## title: A`. `insert-before` is correct. | 4 Swift |
| 13 | An unparseable frontmatter fence is reported as no frontmatter at all, with exit 0 and nothing on stderr. | 3 CLI |
| 14 | `list` exits 0 for a directory that does not exist, and for a path that is a file. | 2 CLI |
| 15 | `--key` on a mapping prints `[AnyHashable("name"): "Jane Roe"]`, a Swift dictionary description whose key order is not stable. | 1 CLI |
| 16 | A null value reaches output as `<null>`. | 2 CLI |

### Byte fidelity

| # | Defect | Pinned by |
| --- | --- | --- |
| 17 | `format` rewrites CRLF line endings as LF. | 1 CLI |
| 18 | `insert-after` and `replace` invent a final newline. | 2 CLI |
| 19 | Blocks the user never touched are re-spelled: `*` bullets become `-`, `***` breaks become `---`, and two trailing spaces become a backslash. | 2 CLI |
| 20 | An ordered list is renumbered, so a list starting at 3 loses its rendered numbering. | 2 CLI |

### Interface

| # | Defect | Pinned by |
| --- | --- | --- |
| 21 | A refusal prints the usage of `md` itself rather than of the subcommand that refused. | 4 CLI |
| 22 | `format` has no `-i` flag, unlike every other command that writes. **Do not add it yet.** `format` still loses HTML blocks, link reference definitions, blockquote paragraph breaks, CRLF endings and list numbering. An `-i` flag would write all of that into the user's file. | 1 CLI |
| 23 | `list --key` breaks its one line per file shape when a value spans lines. | 1 CLI |
| 24 | `list --output json` pretty-prints an empty array over three lines. | 1 CLI |

### Fixed

| # | Defect | Fixed by |
| --- | --- | --- |
| 2 | A soft line break inside a paragraph was dropped with nothing in its place, so `fox\njumps` became `foxjumps`. It hit every wrapped paragraph in every document. | `getNodeText` keeps `CMARK_NODE_SOFTBREAK` as a newline. |
| 3 | A hard line break, two trailing spaces or a trailing backslash, was dropped the same way. | `getNodeText` keeps `CMARK_NODE_LINEBREAK`. See the note below. |
| 5 | Backslash escapes were resolved away, so `\*asterisk\*` was rewritten as emphasis and the paragraph meant something else. | `MarkdownEscaper` puts each needed backslash back. |

**A note on defect 3, because it left something behind.** A hard break has
two spellings, two trailing spaces and a trailing backslash, and both mean
the same break. The block text is markdown source, thus a bare newline would
have said SOFT break where the source said hard, so the fix had to choose a
spelling and it writes the backslash: trailing spaces are invisible, and a
tool that takes off trailing space takes the break with it.

So the break survives and its meaning survives, but a document written with
two spaces comes back with a backslash. That residue is defect 19, not a
separate one: `MarkdownBlock` does not remember which spelling the author
used, the same way it does not remember `*` against `-`. Fix 19 and this
goes with it.

## Where to start

Ordered by tests turned green for code changed, with the cheap and contained
ones first:

1. **9** — one argument, `allowUnicode: true`. It stops `-i` from writing
   escaped bytes into a user's file.
2. **1** — guard with `JSONSerialization.isValidJSONObject`. It removes the
   only crash in the tool, and makes two dead branches live.
3. **10** — five cases, all inside `LinesCommand.run()`.
4. **24**, **14**, **15**, **16**, **23** — one command each, and small.
5. **13**, **21** — small, but each one touches its callers.
6. **12**, **18**, **19**, **20** together. `insert-before` already does the
   right thing: it uses `parseDocument` and splices the source with
   `MarkdownSourceEditor`. `remove`, `replace` and `insert-after` reformat
   the whole document instead. That one difference causes all four defects.
7. **4**, **7**, **17**, **19**, **20** need `MarkdownBlock` to grow: a case
   for raw HTML, a case for a link reference definition, and memory of the
   line ending, the bullet character, the break spelling and the list start
   number. These touch every `switch` over the enum.

## Two traps in measuring this

Both are handled by `scripts/coverage.py`, and both produced a plausible
looking wrong table before they were found.

**`swift test --enable-code-coverage` exits 1 here even when all tests
pass.** SwiftPM merges the profiles itself and fails the command if any one is
truncated. This package always truncates one on purpose:
`testInPlaceWriteFailureLeavesOriginalUntouched` runs `md` under `ulimit -f 2`
to prove a failed write leaves the original alone, and the instrumented
subprocess hits that limit writing its own profile.

**`swift build` does not build test targets.** Paired with `swift test
--skip-build`, that silently measures whatever test bundle is on disk. It
reported 88.73% where the truth was 98.24%, and nothing in the output said so.
`--build-tests` fixes it.
