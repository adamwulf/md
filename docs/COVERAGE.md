# Coverage report

A snapshot, measured 2026-08-04. Regenerate it at any time:

```bash
python3 scripts/coverage.py                # the combined table below
python3 scripts/coverage.py --swift-only
python3 scripts/coverage.py --cli-only
```

Suite sizes at the time of measuring: 612 Swift tests, 392 CLI cases.

## Headline

Coverage of `Sources/` only. Test code and checked out dependencies are
excluded, because their coverage says nothing about this package.

| Measured by | Lines | Functions | Regions |
| --- | --- | --- | --- |
| `swift test` | 98.24% | 93.45% | 95.79% |
| `cli-tests` | 88.73% | 83.84% | 82.97% |
| Both together | **98.24%** | **93.45%** | **95.79%** |

Up from 80.84% / 73.36% / 71.29% at the start of this work.

## Read the third row carefully

**The CLI suite adds no line coverage.** Every line it reaches, a Swift test
reaches too, because the Swift tests call each command's `run()` in process
rather than testing only the helper types around it.

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

A line can be covered and still be wrong. Of the 24 defects listed below,
every one sits on a line that coverage already counted as covered.

So do not read these numbers as "the CLI suite has enough cases". Read
`--swift-only` against `--cli-only` for the thing they do tell you: which
lines rest on one suite alone.

## Per file, both suites together

| File | Lines | Functions | Regions |
| --- | --- | --- | --- |
| `MarkdownKit/MarkdownParser.swift` | 98.36% | 92.00% | 93.70% |
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
| **TOTAL** | **98.24%** | **93.45%** | **95.79%** |

## What the remaining 1.76% is

Not a backlog. Nearly all of it is unreachable by design:

- `??` fallbacks whose left side cannot be nil given the only caller
- the `guard let node = node` nil branches in `MarkdownParser`
- the out of bounds fallback in `calculateRanges`
- the `sigaction` and `chflags` POSIX failure paths in `InputReader`

Two misses are different, and are worth knowing about. The
"serialization failed, fall through" branch at `FormatCommand.swift:75` and
the `catch` at `ListCommand.swift:226` are **dead code today**: the only
realistic failure is the non-finite number below, and it aborts the process
before either can run. Fix that defect and both branches become reachable.

## Defects found: 24

None were fixed. This work was scoped to tests, so that it merges cleanly
with the branches doing the fixing. Every defect is pinned by a test that
holds the CORRECT expectation and is marked as a known failure, so each one
turns green by itself when it is fixed.

- 43 CLI cases carry a `known-fail` file saying what `md` does today, what it
  should do, and what was worked out about the cause.
- 15 `XCTExpectFailure` assertions do the same on the Swift side.

If a marked case starts passing, both suites report it loudly rather than
going quiet. Delete the marker then.

### Crash

| # | Defect |
| --- | --- |
| 1 | `.nan` or `.inf` in frontmatter reaches `JSONSerialization`, which RAISES rather than throws. `md format --frontmatter json` and `md list --format json` abort with SIGABRT. In `list` one bad file takes down a whole directory walk. |

### Data loss

| # | Defect |
| --- | --- |
| 2 | A soft line break inside a paragraph is dropped with nothing in its place, so `fox\njumps` becomes `foxjumps`. Hits every wrapped paragraph in every document. |
| 3 | A hard line break, two trailing spaces, is dropped the same way. |
| 4 | An HTML block is deleted outright. It has no `MarkdownBlock` case. |
| 5 | Backslash escapes are resolved away, so `\*asterisk\*` is rewritten as emphasis and the paragraph means something else. |
| 6 | Two paragraphs in a blockquote are flattened into one run. |
| 7 | An unused link reference definition is deleted. |
| 8 | A list item wrapping to a second source line reformats so the continuation escapes the item. Formatting twice changes the document structure. |
| 9 | `--set` on any key rewrites every non-ASCII value as an escape: `Café` becomes `"Caf\xE9"`. `Yams.dump` is called without `allowUnicode`. With `-i` the escaped bytes land in the user's file. |

### Wrong answers

| # | Defect |
| --- | --- |
| 10 | `lines` counts one line too many. `components(separatedBy: "\n")` leaves an empty element after the final newline. A 3 line file reports 4, an empty file reports 1, and `lines 4` on a 3 line file exits 0 and prints a blank line instead of refusing. |
| 11 | A list block absorbs the blank line below it. A list on lines 3-4 is reported as L3-5, and the printed slice carries the blank line. No other block type does this. |
| 12 | `remove`, `replace` and `insert-after` call `MarkdownParser.parse` instead of `parseDocument`, so YAML frontmatter counts as 2 extra blocks. `md blocks` and `md remove` disagree about the numbering, and an edit can rewrite the frontmatter as `---\n\n## title: A`. `insert-before` is correct. |
| 13 | An unparseable frontmatter fence is reported as no frontmatter at all, with exit 0 and nothing on stderr. |
| 14 | `list` exits 0 for a directory that does not exist, and for a path that is a file. |
| 15 | `--key` on a mapping prints `[AnyHashable("name"): "Jane Roe"]`, a Swift dictionary description whose key order is not stable. |
| 16 | A null value reaches output as `<null>`. |

### Byte fidelity

| # | Defect |
| --- | --- |
| 17 | `format` rewrites CRLF line endings as LF. |
| 18 | `insert-after` and `replace` invent a final newline. |
| 19 | Blocks the user never touched are re-spelled: `*` bullets become `-`, and `***` breaks become `---`. |
| 20 | An ordered list is renumbered, so a list starting at 3 loses its rendered numbering. |

### Interface

| # | Defect |
| --- | --- |
| 21 | A refusal prints the usage of `md` itself rather than of the subcommand that refused. |
| 22 | `format` has no `-i` flag, unlike every other command that writes. |
| 23 | `list --key` breaks its one line per file shape when a value spans lines. |
| 24 | `list --output json` pretty-prints an empty array over three lines. |

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
