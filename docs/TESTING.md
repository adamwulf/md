# Testing

This package has two test suites. They test different things, and you need
both.

| Suite | What it drives | Where it lives | How to run it |
| --- | --- | --- | --- |
| Swift tests | The Swift types, called directly | `Tests/` | `swift test` |
| CLI tests | The built `md` binary, run as a user runs it | `cli-tests/` | `python3 cli-tests/run.py` |

Run both before you say a change is done:

```bash
swift test
python3 cli-tests/run.py
```

## Which suite does a test belong in?

Ask what the test must prove.

**Use a Swift test** when the answer is about a type, a function, or a branch
inside the package. A parser that must give the correct range for a block, a
formatter that must escape a character, an error that must be thrown: all of
these are Swift tests. They are fast, they can reach a private detail, and
they can assert on a value that never reaches the screen.

**Use a CLI test** when the answer is about what a user sees. The exact bytes
on stdout, the exit code, the message on stderr, how a flag parses, what the
file holds after `-i`: all of these are CLI tests. A Swift test cannot reach
them, because it never runs the binary.

When a defect shows both, write both. The CLI test proves the user-visible
symptom is gone. The Swift test holds the line at the level where the defect
lived, and it tells the next reader where to look.

## Swift tests

The tests are XCTest, in two directories:

- `Tests/MarkdownKitTests/` tests the `MarkdownKit` library.
- `Tests/CLITests/` tests the internals of the `md` tool. It does not run the
  binary. It calls the types under `Sources/md/` directly.

```bash
swift test                              # everything
swift test --filter FrontmatterTests    # one test class
swift test --filter testParseTable      # one test
```

### Writing a good one

Name the test for the behaviour it guards, not for the function it calls.
`testRemoveKeepsTheBlankLineBelowIt` tells the next reader what broke.
`testRemove3` does not.

Assert on exact values. A test that only checks a count, or that a result is
not nil, passes for many wrong reasons.

Make each test fail for one reason. When a test asserts five things and the
first one breaks, the other four never run and you learn less.

Read the tests already in the directory before you write your first one, and
follow their shape.

### When a test you wrote fails

Decide honestly which of two things happened.

1. **Your expectation was wrong.** Markdown has many corners. Read the spec
   and the source, then correct your test.
2. **The code is wrong.** Then you found a defect. Do not fix the code inside
   a test task, and do not delete the test. Mark it with `XCTExpectFailure`,
   carrying a message that says what the code does today and what it should
   do instead.

Never weaken a correct assertion to make a test green. A test that asserts
the wrong thing is worse than no test.

## CLI tests

`cli-tests/README.md` documents this suite in full: every file a case
directory can hold, how `args` is quoted, how `then-args` chains a second
command, and how the byte comparison reports an invisible difference. **Read
it before you add a case.** What follows is only the shape of the thing.

Each case is a directory of plain files. Nothing is a script:

```
cli-tests/remove-keeps-the-heading-above-it/
  about          what this case guards, in prose
  args           the arguments passed to md, without the leading "md"
  input.md       the fixture
  expected.md    the exact bytes md must print to stdout
```

The runner builds `md` once, copies the fixture to a scratch directory, runs
the binary against the copy, and compares raw bytes. Your fixture in the
repository is never edited, so a case can safely use `-i`.

```bash
python3 cli-tests/run.py                       # every case
python3 cli-tests/run.py remove-keeps-a-table  # one case
python3 cli-tests/run.py --list                # names only
python3 cli-tests/run.py --no-build            # skip swift build
```

### The comparison is byte for byte

Nothing is normalized. A final newline that should not be there is a failure.
So is a lost CR, and so is a trailing space.

This matters more than it sounds, because a diff draws all three as nothing at
all. The runner therefore says in words what the diff hides, before it prints
the diff:

```
NOTE: The only difference is a final newline: actual invented one that
      expected does not have.
```

### Write `expected.md` by hand

Work out what the command should print, and type that. Do not run the command
and paste its output. Captured output records what the tool does today, which
is the exact thing under test.

The runner has a flag that rewrites the expected files, and it is deliberately
long and awkward:
`--rewrite-expected-files-i-have-read-the-diff`. Use it only after you have
read the diff and decided the new bytes are correct.

### `known-fail`: a case that describes an open defect

Add a `known-fail` file to a case when `md` is wrong and you are not fixing it
now. Leave the correct bytes in `expected.md`, and write into the marker what
`md` does today, what it should do, and anything you worked out about the
cause.

The runner reports the case as `KNOWN FAIL` and does not count it toward the
exit code, so the suite stays green while the defect is open. Together, the
markers are a worklist.

Delete the marker when the defect is fixed. If a case marked `known-fail`
starts passing, the runner reports `UNEXPECTED PASS` and exits non-zero, on
purpose: a stale marker hides the next regression.

## Coverage

```bash
python3 scripts/coverage.py                  # both suites, merged
python3 scripts/coverage.py --swift-only     # swift test alone
python3 scripts/coverage.py --cli-only       # cli-tests alone
python3 scripts/coverage.py --html cov-html  # a browsable report
python3 scripts/coverage.py --show           # annotated source
```

### Why the script exists

To measure the two suites together, and to let you see them apart.

Where the package stands today, on `Sources/` only:

| Measured by | Lines | Functions | Regions |
| --- | --- | --- | --- |
| `swift test` | 98.24% | 93.45% | 95.79% |
| `cli-tests` | 88.73% | 83.84% | 82.97% |
| Both together | 98.24% | 93.45% | 95.79% |

Read the last row carefully. **The CLI suite adds no line coverage at all.**
Every line it reaches, a Swift test already reaches, because the Swift tests
call each command's `run()` in process rather than only testing helper types.

That is worth stating plainly, because it is easy to draw the wrong
conclusion from it. It does not mean the CLI suite is redundant. It means
line coverage is the wrong measure of what that suite is for. What it defends
is everything a coverage number cannot see:

- the exact bytes on stdout, including a final newline, a CR, and a trailing
  space
- the exit code
- what the file holds after `-i`
- how ArgumentParser reads a real command line
- **a crash.** `md format --frontmatter json` once aborted with SIGABRT on a
  frontmatter value of `.nan`. No Swift test could safely provoke that abort,
  so two CLI cases pinned it as an exit code and now guard the clean refusal.

A line can be covered and still be wrong. The CLI suite is what says whether
it is right.

So do not use these numbers to decide the CLI suite has enough cases. Use
`--swift-only` against `--cli-only` for what it does tell you: which lines
rest on one suite alone, and would go undefended if that suite were skipped.

### Two traps the script handles for you

**`swift test --enable-code-coverage` exits 1 on this package even when every
test passes.** SwiftPM merges the profiles itself when the run ends, and it
fails the whole command if any one profile is truncated.

This package reliably produces a truncated one, and it is not a bug. The test
`testInPlaceWriteFailureLeavesOriginalUntouched`, at
`Tests/CLITests/CommandTests.swift:540`, runs the `md` binary under
`ulimit -f 2` on purpose, to prove that a failed write leaves the original
file alone. The instrumented subprocess hits that file size limit while
writing its own profile, so the profile lands truncated.

The script therefore builds with coverage, runs the tests without that flag,
and merges the profiles itself with `-failure-mode=all`, which skips a
truncated profile with a warning instead of failing. The exit code then means
what it says: the tests passed, or they did not.

If you would rather have SwiftPM do the merge, skip that one test:

```bash
swift test --enable-code-coverage --skip testInPlaceWriteFailureLeavesOriginalUntouched
```

That writes `.build/*/debug/codecov/md.json`, which holds the same numbers.
It measures `swift test` alone, so it cannot show you what the CLI tests
cover.

**A stale profile inflates the next number.** The script clears the profile
directory of each suite it is about to run, so `--cli-only` reports the CLI
tests alone and not the CLI tests plus whatever the last run left behind.

## Adding a test: the short version

1. Decide which suite the question belongs in, using the table at the top.
2. Name the case or the test function for what it guards.
3. Write the expected result by hand, before you run anything.
4. Run it. If it passes, you have a regression guard.
5. If it fails, decide whether your expectation or the code is wrong. When the
   code is wrong, keep the correct expectation and mark it: a `known-fail`
   file for a CLI case, `XCTExpectFailure` for a Swift test.
6. Run both suites and `python3 scripts/coverage.py` before you commit.
