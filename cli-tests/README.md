# cli-tests

End to end tests for the `md` command line tool. Each case is a directory of
plain files: a fixture, the arguments to run, and the exact bytes the command
should print. `run.py` runs them all and reports PASS, FAIL, or KNOWN FAIL.

These tests exist so that nobody has to rebuild a repro by hand. If you find a
defect, add a case for it before you fix it. If you fix a defect, the case that
described it should start passing.

## Running

```bash
python3 cli-tests/run.py                              # every case
python3 cli-tests/run.py replace-with-html-comment    # one case
python3 cli-tests/run.py replace-with-task-list format-drops-html-block
python3 cli-tests/run.py --list                       # names only
python3 cli-tests/run.py --verbose                    # show known-fail diffs too
```

The runner builds once with `swift build`, then drives `.build/debug/md`
directly. It never calls `swift run`, which would pay the build check on every
case.

It exits 0 when the only failures are the ones marked known-fail, and non-zero
as soon as a real failure appears, so it can gate a merge.

Useful options:

| Option | What it does |
| --- | --- |
| `-v`, `--verbose` | Show the diff for known-fail cases as well |
| `--list` | Print the case names and exit |
| `--no-build` | Skip `swift build`; the binary must already exist |
| `--keep-scratch` | Keep the scratch directories for inspection |

## What a case directory holds

Only `args` and `expected.md` are required. Everything else is optional.

| File | Meaning |
| --- | --- |
| `args` | The arguments passed to `md`. Required. |
| `input.md` | The fixture the command runs against. Copied to a scratch directory first. |
| `expected.md` | The exact bytes the command must print to stdout. Required. |
| `expected-file.md` | For a case using `-i`: the exact bytes of `input.md` after the run. |
| `expected-exit` | The expected exit code. Defaults to 0. |
| `expected-stderr` | The exact bytes the command must print to stderr. |
| `stdin.md` | Content piped to the command's stdin, for `--stdin` cases. |
| `then-args` | A second `md` command, fed the first one's stdout. See below. |
| `known-fail` | Marker saying this case is a known open defect, and why. |
| `about` | Free text saying what the case guards. Not used by the runner. |

Any other file in the directory is treated as fixture data and copied to the
scratch directory alongside `input.md`.

### `args`

One command line, without the leading `md`. It is parsed with `shlex.split`
using POSIX quoting rules and handed straight to the process. No shell is
involved, so nothing in a fixture can be expanded or executed.

```
replace 2 "New paragraph." --file input.md
```

A quoted argument may span several lines, and the line breaks are part of the
argument:

```
replace 2 "<!-- note -->

Real paragraph." --file input.md
```

Quote with single quotes when the content itself contains double quotes:

```
insert-after 1 '<div class="callout">
  <p>Hello.</p>
</div>' --file input.md
```

When the content starts with a hyphen, put `--file` before the index and use
`--` to end option parsing. Otherwise ArgumentParser reads the leading hyphen as
an option and fails before `md` sees the content:

```
replace --file input.md 2 -- "- [ ] first task
- [x] second task"
```

### `then-args`

A second `md` invocation. The first command's stdout is piped to its stdin, and
`expected.md` then describes the SECOND command's output. Use it to assert a
property of the result rather than its exact bytes:

```
args:       replace 1 "Replacement paragraph." --file input.md
then-args:  blocks --count --stdin
expected:   4
```

The first command must exit 0, or the case fails and says so.

## Comparison is byte for byte

Nothing is normalized. A trailing newline that should not be there is a failure,
and so is a lost CR.

This matters more than it sounds. Several of the defects this suite tracks ARE a
missing or an invented final newline, and a diff renders that as nothing at all.
So when the only difference is a final newline, a CR, or trailing whitespace,
the runner says so in words before it prints the diff:

```
NOTE: The only difference is a final newline: actual invented one that expected
      does not have.
```

In the diff itself, `<LF>` marks the end of a line, `<NO FINAL NEWLINE>` marks a
last line with no terminator, and `<CR>`, `<TAB>` and `<SPACE>` show characters
you would otherwise not see.

Fixtures are copied to a scratch directory before each run, so a case using `-i`
edits the copy and the fixture in this repository is never touched.

## Known failures

A `known-fail` file marks a case that describes an OPEN DEFECT. The expected
output in that directory is what `md` SHOULD print, not what it prints today.

The runner reports such a case as `KNOWN FAIL` and does not count it toward the
exit code, so the suite stays green while the defect is open. Together the
markers are the fix agent's worklist: run `--list` to see them, or `--verbose`
to read the diffs.

Write into the marker WHY the case fails: what the tool does today, what it
should do, and anything you learned about the cause. That text is the whole
value of the marker, and it is printed when the case runs.

**Delete the marker when the defect is fixed.** If a case marked known-fail
starts passing, the runner reports `UNEXPECTED PASS` and exits non-zero:

```
UNEXPECTED PASS replace-with-task-list
                This case is marked known-fail but it PASSED.
                Someone fixed the defect. Read the marker, confirm the fix,
                then delete replace-with-task-list/known-fail.
```

That is deliberate. A stale marker hides a real regression later, because the
case can then break again without anyone noticing.

A malformed case, for example an unreadable `args` file or a missing
`expected.md`, is always a real FAIL. A known-fail marker describes a defect in
`md` and cannot excuse broken fixtures.

## Adding a case

1. Make a directory named for what it tests, not for the command it runs.
   `replace-keeps-crlf-line-endings`, not `replace-test-4`.
2. Add `input.md` and `args`.
3. Write `expected.md` by hand: what the command SHOULD print.
4. Run it. If it passes, you have a regression guard.
5. If it fails and the tool is wrong, add a `known-fail` file explaining the
   defect. If the tool is right, fix your expectation.
6. Add an `about` file if the point of the case is not obvious from its name.

Write the expected output by hand rather than capturing it. Capturing records
what the tool does today, which is exactly the thing under test.

## Rewriting expected files

There is a flag for it, and it is deliberately long:

```bash
python3 cli-tests/run.py --rewrite-expected-files-i-have-read-the-diff
```

It rewrites `expected.md`, and any `expected-file.md`, `expected-stderr` or
`expected-exit` the case already declares, from whatever the tool prints today.

**Never use it to make a failing test pass without reading the diff first.** A
failing test is either a real defect or a real change of intent, and only you
can tell those apart. Read the diff, decide which it is, and only then rewrite.

Cases marked known-fail are skipped unless you name them on the command line,
because rewriting one would freeze the defect in place as the expected result.

## Byte exact fixtures

Some fixtures are byte exact on purpose:

- `replace-keeps-crlf-line-endings` has CRLF endings in both `input.md` and
  `expected.md`.
- `remove-last-block-invents-final-newline` has no final newline in `input.md`
  or `expected-file.md`.

Three cases hold a NO-BREAK SPACE, U+00A0, two bytes that look exactly like a
space on every screen you will read them on. Check `wc -c` after editing any of
them, and never retype the line:

| Case | Where the U+00A0 is | Bytes |
| --- | --- | --- |
| `remove-keeps-a-paragraph-of-one-non-breaking-space` | line 3 of `input.md`, line 1 of `expected.md` | 25 / 14 |
| `insert-after-does-not-fuse-into-a-non-breaking-space-paragraph` | line 2 of `input.md` | 10 |
| `replace-with-a-non-breaking-space-keeps-the-block` | inside the quotes in `args`, line 3 of `expected.md` | 31 / 11 |

So does every case that pins a frontmatter no-op, where `expected-file.md` is a
byte for byte copy of `input.md`:

| Case | What its bytes are |
| --- | --- |
| `frontmatter-remove-key-keeps-crlf-line-endings` | CRLF, 59 bytes |
| `frontmatter-remove-key-keeps-a-readable-crlf-fence` | CRLF, 51 bytes |
| `frontmatter-remove-key-keeps-toml-crlf-line-endings` | CRLF, 55 bytes |
| `frontmatter-remove-key-keeps-json-crlf-line-endings` | CRLF, 59 bytes |
| `frontmatter-remove-key-keeps-lone-cr-line-endings` | lone CR, no LF at all, 45 bytes |
| `frontmatter-remove-key-keeps-a-fence-with-no-final-newline` | ends at `---`, 16 bytes |

`cli-tests/.gitattributes` sets `* -text` so git never converts line endings
here. Do not "tidy" those files, and check `wc -c` after editing anything in
those directories.
