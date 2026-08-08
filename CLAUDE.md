# md

`md` is a command-line tool for markdown, built on the `MarkdownKit` library.
This file is a short map. The linked docs are the authority — read them before
you change code or tests.

## Layout

- `Sources/md/` — the `md` CLI (commands live in `Sources/md/Commands/`).
- `Sources/MarkdownKit/` — the parser and formatter the CLI uses.
- `Tests/` — Swift tests (XCTest): `MarkdownKitTests/` and `CLITests/`.
- `cli-tests/` — black-box CLI cases that run the built binary.
- `docs/` — `TESTING.md` and `COVERAGE.md`.
- `scripts/coverage.py` — the coverage tool.

## Build and run the local `md`

- Build once: `swift build`.
- Run the local build directly: `.build/debug/md <args>`.
- Do NOT use `swift run md …` to test the tool. It re-checks the build on every
  call. The CLI harness drives `.build/debug/md` for the same reason — see
  `cli-tests/README.md`.

## Test — run BOTH before you call a change done

```bash
swift test                 # Swift types and each command's run(), in process
python3 cli-tests/run.py   # the built binary, run as a user runs it
```

- Which suite a test belongs in, and how to write a good one: `docs/TESTING.md`.
- CLI case layout (`args`, `input.md`, `expected.md`, `known-fail`, `wont-fix`,
  `expected-file.md`): `cli-tests/README.md`.

## Coverage

```bash
python3 scripts/coverage.py
```

Why the numbers read as they do, and two measurement traps the script handles
for you: `docs/COVERAGE.md`.

## How this project tracks defects (test-driven)

- A defect is pinned by a test that holds the CORRECT expectation, so it turns
  green by itself when the defect is fixed.
- A CLI case marks an open defect with a `known-fail` file, or one the project
  has decided to leave with a `wont-fix` file; a Swift test uses
  `XCTExpectFailure`. The suite stays green while the defect is open.
- Write `expected.md` by hand. Do NOT paste the tool's current output, and do
  NOT weaken a correct expectation to make a test pass. See `docs/TESTING.md`.
- The defect ledger — found, fixed, open, won't fix, withdrawn — lives in
  `docs/COVERAGE.md`. When you fix a defect, delete its marker and move it to
  fixed in the ledger. When a `known-fail` case starts passing, the runner
  reports `UNEXPECTED PASS` on purpose: reclassify it, do not ignore it.
