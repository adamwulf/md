#!/usr/bin/env python3
"""Shell-free CLI test harness for the `md` tool.

Every case is a directory beside this script. The harness builds `md` once,
copies each fixture to a scratch directory, runs the built binary against the
copy, and compares raw bytes.

Comparisons are made on bytes, never on decoded text. Several of the defects
this suite exists to catch are a missing or an invented final newline, or a
lost CR. A comparison that normalises either of those is worthless here.

Run `python3 cli-tests/run.py --help` for the options, and read
cli-tests/README.md for the layout of a case directory.
"""

import argparse
import difflib
import shlex
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

TESTS_DIR = Path(__file__).resolve().parent
REPO_ROOT = TESTS_DIR.parent

# Names the harness gives meaning to. Anything else in a case directory is
# treated as fixture data and copied to the scratch directory.
ARGS = "args"
THEN_ARGS = "then-args"
INPUT = "input.md"
STDIN = "stdin.md"
EXPECTED_STDOUT = "expected.md"
EXPECTED_FILE = "expected-file.md"
EXPECTED_EXIT = "expected-exit"
EXPECTED_STDERR = "expected-stderr"
KNOWN_FAIL = "known-fail"
WONT_FIX = "wont-fix"
ABOUT = "about"

CONTROL_FILES = frozenset([
    ARGS, THEN_ARGS, STDIN, EXPECTED_STDOUT, EXPECTED_FILE,
    EXPECTED_EXIT, EXPECTED_STDERR, KNOWN_FAIL, WONT_FIX, ABOUT,
])

BLESS_FLAG = "--rewrite-expected-files-i-have-read-the-diff"
TIMEOUT_SECONDS = 60

PASS = "PASS"
FAIL = "FAIL"
KNOWN = "KNOWN FAIL"
WONTFIX = "WONT FIX"
UNEXPECTED = "UNEXPECTED PASS"


class CaseError(Exception):
    """A case directory is malformed, or the binary could not be run.

    This is a problem with the harness or the fixture, not a defect in `md`,
    so a known-fail marker does not excuse it.
    """


# ---------------------------------------------------------------- rendering

def render_lines(data):
    """Render bytes as printable lines with the invisible characters shown.

    A CR becomes <CR>, a tab becomes <TAB>, a trailing space becomes <SPACE>,
    and the end of every line is marked so that a missing final newline is
    visible in a diff instead of silent.
    """
    if data == b"":
        return []
    parts = data.split(b"\n")
    lines = []
    for index, part in enumerate(parts):
        is_last = index == len(parts) - 1
        if is_last and part == b"":
            # The data ended with a newline, so there is no further line.
            break
        text = part.decode("utf-8", errors="backslashreplace")
        text = text.replace("\r", "<CR>").replace("\t", "<TAB>")
        without_trailing = text.rstrip(" ")
        if without_trailing != text:
            text = without_trailing + "<SPACE>" * (len(text) - len(without_trailing))
        lines.append(text + ("<NO FINAL NEWLINE>" if is_last else "<LF>"))
    return lines


def difference_notes(expected, actual):
    """Say in words what a diff renders invisibly."""
    notes = []
    if actual == expected + b"\n":
        notes.append(
            "The only difference is a final newline: actual invented one that "
            "expected does not have."
        )
    elif expected == actual + b"\n":
        notes.append(
            "The only difference is a final newline: expected has one and "
            "actual dropped it."
        )

    if b"\r" in expected or b"\r" in actual:
        if expected.replace(b"\r\n", b"\n") == actual:
            notes.append(
                "The only difference is line endings: expected is CRLF, "
                "actual is LF. Actual lost every CR."
            )
        elif actual.replace(b"\r\n", b"\n") == expected:
            notes.append(
                "The only difference is line endings: expected is LF, "
                "actual is CRLF. Actual invented a CR on every line."
            )

    if not notes:
        expected_stripped = [line.rstrip() for line in expected.split(b"\n")]
        actual_stripped = [line.rstrip() for line in actual.split(b"\n")]
        if expected_stripped == actual_stripped:
            notes.append(
                "The only difference is whitespace at the end of one or more "
                "lines."
            )
    return notes


def compare(label, expected, actual):
    """Return None when the bytes match, else a list of report lines."""
    if expected == actual:
        return None
    report = ["%s differs (expected %d bytes, actual %d bytes)"
              % (label, len(expected), len(actual))]
    for note in difference_notes(expected, actual):
        report.append("NOTE: " + note)
    report.extend(difflib.unified_diff(
        render_lines(expected),
        render_lines(actual),
        fromfile="expected " + label,
        tofile="actual " + label,
        lineterm="",
    ))
    return report


# ------------------------------------------------------------------ helpers

def die(message):
    sys.stderr.write("cli-tests: %s\n" % message)
    raise SystemExit(2)


def read_bytes(path):
    try:
        return path.read_bytes()
    except OSError as error:
        raise CaseError("cannot read %s: %s" % (path.name, error))


def write_bytes(path, data):
    try:
        path.write_bytes(data)
    except OSError as error:
        raise CaseError("cannot write %s: %s" % (path.name, error))


def split_args(path):
    """Parse an args file with POSIX quoting rules and no shell.

    Nothing in a fixture is expanded or executed: the tokens go straight to
    subprocess with shell=False.
    """
    text = read_bytes(path).decode("utf-8", errors="replace")
    try:
        argv = shlex.split(text)
    except ValueError as error:
        raise CaseError("cannot parse %s: %s" % (path.name, error))
    if not argv:
        raise CaseError("%s is empty; it must hold the arguments passed to md"
                        % path.name)
    return argv


def build():
    print("Building md with swift build ...")
    try:
        result = subprocess.run(["swift", "build"], cwd=str(REPO_ROOT))
    except OSError as error:
        die("cannot run swift build: %s" % error)
    if result.returncode != 0:
        die("swift build failed with exit code %d" % result.returncode)
    print("")


def resolve_binary():
    candidate = REPO_ROOT / ".build" / "debug" / "md"
    if candidate.is_file():
        return candidate
    # Fall back to asking SwiftPM, in case the build directory is elsewhere.
    try:
        result = subprocess.run(
            ["swift", "build", "--show-bin-path"],
            cwd=str(REPO_ROOT),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except OSError as error:
        die("cannot find the md binary and cannot run swift: %s" % error)
    if result.returncode == 0:
        reported = result.stdout.decode("utf-8", errors="replace").strip()
        if reported:
            fallback = Path(reported) / "md"
            if fallback.is_file():
                return fallback
    die("cannot find the md binary at %s. Run swift build first." % candidate)


def run_command(binary, argv, cwd, stdin_bytes):
    try:
        return subprocess.run(
            [str(binary)] + argv,
            cwd=str(cwd),
            input=stdin_bytes,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=TIMEOUT_SECONDS,
        )
    except subprocess.TimeoutExpired:
        raise CaseError("md did not finish in %d seconds: md %s"
                        % (TIMEOUT_SECONDS, " ".join(argv)))
    except OSError as error:
        raise CaseError("cannot run the md binary: %s" % error)


# ------------------------------------------------------------- case running

def execute(directory, binary, scratch):
    """Run a case in the scratch directory and return (result, argv).

    `result` is the completed process whose streams the case asserts on. When
    the case declares a `then-args` command, that is the second process, fed
    the first one's stdout, and `argv` describes the whole chain.
    """
    for entry in sorted(directory.iterdir()):
        if entry.name in CONTROL_FILES:
            continue
        try:
            if entry.is_dir():
                # A subdirectory is staged whole, so that a case can give a
                # command a tree to walk. `md list -r` cannot be tested any
                # other way: it takes a directory, not a file.
                shutil.copytree(str(entry), str(scratch / entry.name))
            elif entry.is_file():
                shutil.copyfile(str(entry), str(scratch / entry.name))
        except OSError as error:
            raise CaseError("cannot copy fixture %s: %s"
                            % (entry.name, error))

    stdin_path = directory / STDIN
    stdin_bytes = read_bytes(stdin_path) if stdin_path.is_file() else b""

    argv = split_args(directory / ARGS)
    result = run_command(binary, argv, scratch, stdin_bytes)

    then_path = directory / THEN_ARGS
    if not then_path.is_file():
        return result, argv

    if result.returncode != 0:
        raise CaseError(
            "the first command failed with exit code %d, so the %s command "
            "could not run.\n  command: md %s\n  stderr: %s"
            % (result.returncode, THEN_ARGS, " ".join(argv),
               result.stderr.decode("utf-8", errors="replace").strip())
        )

    then_argv = split_args(then_path)
    then_result = run_command(binary, then_argv, scratch, result.stdout)
    return then_result, argv + ["|", "md"] + then_argv


def check(directory, result):
    """Compare the run against every expectation the case declares."""
    failures = []

    expected_stdout_path = directory / EXPECTED_STDOUT
    if not expected_stdout_path.is_file():
        raise CaseError(
            "no %s. Write the expected stdout by hand, or create it from the "
            "actual output with %s." % (EXPECTED_STDOUT, BLESS_FLAG)
        )
    report = compare("stdout", read_bytes(expected_stdout_path), result.stdout)
    if report:
        failures.append(report)

    expected_exit = 0
    exit_path = directory / EXPECTED_EXIT
    if exit_path.is_file():
        raw = read_bytes(exit_path).decode("utf-8", errors="replace").strip()
        try:
            expected_exit = int(raw)
        except ValueError:
            raise CaseError("%s must hold an integer, got %r"
                            % (EXPECTED_EXIT, raw))
    if result.returncode != expected_exit:
        failures.append([
            "exit code differs (expected %d, actual %d)"
            % (expected_exit, result.returncode)
        ])

    stderr_path = directory / EXPECTED_STDERR
    if stderr_path.is_file():
        report = compare("stderr", read_bytes(stderr_path), result.stderr)
        if report:
            failures.append(report)

    return failures


def check_edited_file(directory, scratch):
    """Compare the edited copy of the fixture for a case that uses -i."""
    expected_path = directory / EXPECTED_FILE
    if not expected_path.is_file():
        return []
    edited = scratch / INPUT
    if not edited.is_file():
        return [["%s is declared but %s does not exist in the scratch "
                 "directory after the run" % (EXPECTED_FILE, INPUT)]]
    report = compare("edited " + INPUT, read_bytes(expected_path),
                     read_bytes(edited))
    return [report] if report else []


def bless(directory, result, scratch):
    """Rewrite the expected files from the actual output."""
    written = []
    write_bytes(directory / EXPECTED_STDOUT, result.stdout)
    written.append(EXPECTED_STDOUT)

    expected_file_path = directory / EXPECTED_FILE
    if expected_file_path.is_file():
        edited = scratch / INPUT
        if edited.is_file():
            write_bytes(expected_file_path, read_bytes(edited))
            written.append(EXPECTED_FILE)

    stderr_path = directory / EXPECTED_STDERR
    if stderr_path.is_file():
        write_bytes(stderr_path, result.stderr)
        written.append(EXPECTED_STDERR)

    exit_path = directory / EXPECTED_EXIT
    if exit_path.is_file() or result.returncode != 0:
        write_bytes(exit_path, ("%d\n" % result.returncode).encode("utf-8"))
        written.append(EXPECTED_EXIT)

    return written


def run_case(name, binary, options):
    """Run one case and return (status, report_lines)."""
    directory = TESTS_DIR / name
    known_fail_marker = directory / KNOWN_FAIL
    wont_fix_marker = directory / WONT_FIX
    is_known_fail = known_fail_marker.is_file()
    is_wont_fix = wont_fix_marker.is_file()
    scratch = Path(tempfile.mkdtemp(prefix="md-cli-test-%s-" % name))

    try:
        try:
            if is_known_fail and is_wont_fix:
                # The two markers state opposite intentions — a defect still to
                # fix versus one the project has decided to leave. A case
                # declares one, not both.
                return FAIL, ["a case cannot have both a %s and a %s marker; "
                              "keep the one that states the decision"
                              % (KNOWN_FAIL, WONT_FIX)]

            result, argv = execute(directory, binary, scratch)

            if options.bless:
                written = bless(directory, result, scratch)
                return PASS, ["rewrote " + ", ".join(written)]

            failures = check(directory, result)
            failures.extend(check_edited_file(directory, scratch))

            lines = []
            # A known-fail case pins a defect still to be fixed; a wont-fix case
            # pins one the project has decided to leave alone. Both keep the
            # CORRECT expectation and both are tolerated while they fail, so the
            # suite stays green. Both also report an unexpected pass if the
            # behaviour ever changes, so a stale marker cannot hide a regression.
            if is_known_fail or is_wont_fix:
                marker_path = known_fail_marker if is_known_fail else wont_fix_marker
                status = KNOWN if is_known_fail else WONTFIX
                label = KNOWN_FAIL if is_known_fail else WONT_FIX
                reason = read_bytes(marker_path).decode(
                    "utf-8", errors="replace").strip()
                if not failures:
                    lines.append("This case is marked %s but it PASSED."
                                 % label)
                    lines.append("The behaviour changed. Read the marker, "
                                 "confirm it, then delete %s/%s and update the "
                                 "ledger." % (name, label))
                    if reason:
                        lines.extend("  marker: " + line
                                     for line in reason.splitlines())
                    return UNEXPECTED, lines
                first = reason.splitlines()[0] if reason else "(marker is empty)"
                lines.append("reason: " + first)
                if options.verbose:
                    for failure in failures:
                        lines.extend(failure)
                else:
                    lines.append("Run with --verbose to see the diff.")
                return status, lines

            if failures:
                for failure in failures:
                    lines.extend(failure)
                lines.append("command: md " + " ".join(argv))
                if options.keep_scratch:
                    lines.append("scratch: %s" % scratch)
                return FAIL, lines

            return PASS, []
        except CaseError as error:
            # A malformed case is always a real failure. A known-fail or
            # wont-fix marker describes md's behaviour, and cannot excuse
            # broken fixtures.
            return FAIL, str(error).splitlines()
    finally:
        if options.keep_scratch:
            print("  scratch kept for %s: %s" % (name, scratch))
        else:
            shutil.rmtree(str(scratch), ignore_errors=True)


# --------------------------------------------------------------------- main

def discover():
    if not TESTS_DIR.is_dir():
        die("%s does not exist" % TESTS_DIR)
    return sorted(entry.name for entry in TESTS_DIR.iterdir()
                  if entry.is_dir() and (entry / ARGS).is_file())


def parse_options(argv):
    parser = argparse.ArgumentParser(
        prog="python3 cli-tests/run.py",
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
        # Prefix matching would let --rewrite stand for the bless flag, and
        # that flag must stay hard to trigger by accident.
        allow_abbrev=False,
        epilog=(
            "%s rewrites the expected files from whatever the tool prints "
            "today.\nIt MUST NEVER be used to make a failing test pass "
            "without reading the diff\nfirst. A failing test is either a real "
            "defect or a real change of intent, and\nonly you can tell them "
            "apart. Cases marked known-fail are skipped by this flag\nunless "
            "you name them on the command line, because rewriting them would "
            "freeze\nthe defect in place as the expected result." % BLESS_FLAG
        ),
    )
    parser.add_argument(
        "names", nargs="*",
        help="case directories to run; default is every case",
    )
    parser.add_argument(
        "-v", "--verbose", action="store_true",
        help="also show the diff for cases marked known-fail",
    )
    parser.add_argument(
        "--list", action="store_true", dest="list_only",
        help="list the case names and exit",
    )
    parser.add_argument(
        "--keep-scratch", action="store_true",
        help="keep the scratch directories for inspection",
    )
    parser.add_argument(
        "--no-build", action="store_true",
        help="skip swift build; the binary must already be built",
    )
    parser.add_argument(
        BLESS_FLAG, action="store_true", dest="bless",
        help="rewrite expected files from the actual output; read the epilog",
    )
    return parser.parse_args(argv)


def main(argv):
    options = parse_options(argv)
    available = discover()

    if options.list_only:
        for name in available:
            if (TESTS_DIR / name / KNOWN_FAIL).is_file():
                marker = " (known-fail)"
            elif (TESTS_DIR / name / WONT_FIX).is_file():
                marker = " (wont-fix)"
            else:
                marker = ""
            print(name + marker)
        return 0

    if not available:
        die("no cases found in %s" % TESTS_DIR)

    if options.names:
        unknown = [name for name in options.names if name not in available]
        if unknown:
            die("no such case: %s\navailable cases:\n  %s"
                % (", ".join(unknown), "\n  ".join(available)))
        selected = options.names
    else:
        selected = available

    if options.bless:
        if not options.names:
            selected = [name for name in selected
                        if not (TESTS_DIR / name / KNOWN_FAIL).is_file()
                        and not (TESTS_DIR / name / WONT_FIX).is_file()]
            skipped = len(available) - len(selected)
            if skipped:
                print("Skipping %d case(s) marked known-fail or wont-fix. Name "
                      "them explicitly to rewrite them." % skipped)
        print("Rewriting expected files for %d case(s)." % len(selected))
        print("")

    if not options.no_build:
        build()
    binary = resolve_binary()

    counts = {PASS: 0, FAIL: 0, KNOWN: 0, WONTFIX: 0, UNEXPECTED: 0}
    unexpected_names = []

    for name in selected:
        status, lines = run_case(name, binary, options)
        counts[status] += 1
        if status == UNEXPECTED:
            unexpected_names.append(name)
        print("%-15s %s" % (status, name))
        for line in lines:
            print("                %s" % line)
        if lines and status in (FAIL, UNEXPECTED):
            print("")

    print("")
    print("-" * 68)
    summary = ("%d case(s): %d passed, %d failed, %d known-fail"
               % (len(selected), counts[PASS], counts[FAIL], counts[KNOWN]))
    if counts[WONTFIX]:
        summary += ", %d wont-fix" % counts[WONTFIX]
    if counts[UNEXPECTED]:
        summary += ", %d unexpected pass" % counts[UNEXPECTED]
    print(summary)

    if unexpected_names:
        print("")
        print("%d case(s) marked known-fail or wont-fix are now PASSING:"
              % len(unexpected_names))
        for name in unexpected_names:
            print("  %s" % name)
        print("Read each marker, confirm the change is real, then delete the "
              "marker file and update the ledger.")

    return 1 if (counts[FAIL] or counts[UNEXPECTED]) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
