#!/usr/bin/env python3
"""Measure line coverage of the `md` package across BOTH test suites.

The package is tested two ways, and each one reaches code the other cannot:

  * `swift test` drives the Swift types directly. It never runs the binary,
    so argument parsing, exit codes, and everything a subcommand does with
    its parsed options stay dark.
  * `cli-tests/run.py` drives the built binary the way a person does. It
    reaches all of that, but only through the surface the CLI exposes.

Measuring either one alone understates the package. This script runs both
against the same instrumented build, merges the profiles, and reports the
union. It can also report either suite on its own, so you can see which
lines only the CLI tests reach.

Run `python3 scripts/coverage.py --help` for the options, and read
docs/TESTING.md for how the two suites fit together.
"""

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
CLI_TESTS = REPO_ROOT / "cli-tests" / "run.py"

# Coverage of the test code itself, or of a checked out dependency, tells us
# nothing about the package. Report only what lives in Sources/.
IGNORE_REGEX = r"\.build|/Tests/|checkouts"

SWIFT = "swift"
XCRUN = "xcrun"


def die(message):
    sys.stderr.write("coverage: %s\n" % message)
    raise SystemExit(2)


def run(argv, cwd=None, env=None, capture=False):
    """Run a command, returning it. Dies if the command cannot start."""
    try:
        return subprocess.run(
            argv,
            cwd=str(cwd) if cwd else None,
            env=env,
            stdout=subprocess.PIPE if capture else None,
            stderr=subprocess.PIPE if capture else None,
        )
    except OSError as error:
        die("cannot run %s: %s" % (argv[0], error))


def bin_path():
    """Ask SwiftPM where it puts the build, rather than guessing."""
    result = run([SWIFT, "build", "--show-bin-path"], cwd=REPO_ROOT, capture=True)
    if result.returncode != 0:
        die("cannot find the build directory:\n%s"
            % result.stderr.decode("utf-8", errors="replace").strip())
    reported = result.stdout.decode("utf-8", errors="replace").strip()
    if not reported:
        die("swift build --show-bin-path printed nothing")
    return Path(reported)


def test_binary(build_dir):
    """Find the executable inside the .xctest bundle.

    llvm-cov needs the binary that holds the instrumented code, not the
    bundle directory that wraps it.
    """
    bundles = sorted(build_dir.glob("*.xctest"))
    if not bundles:
        die("no .xctest bundle in %s. Run swift test first." % build_dir)
    bundle = bundles[0]
    inner = bundle / "Contents" / "MacOS" / bundle.stem
    if inner.is_file():
        return inner           # macOS wraps the binary in a bundle
    if bundle.is_file():
        return bundle          # Linux builds a bare executable
    die("cannot find the test binary inside %s" % bundle)


def clear_profiles(directory):
    """Start from an empty profile directory.

    A stale .profraw from an earlier run would be merged into this one and
    quietly inflate the result.
    """
    if directory.is_dir():
        shutil.rmtree(str(directory), ignore_errors=True)
    directory.mkdir(parents=True, exist_ok=True)


def build(options):
    """Build the binary AND the test bundle, both instrumented.

    --build-tests is not optional here. Plain `swift build` leaves the test
    targets alone, and run_swift_tests passes --skip-build, so without it the
    run would silently measure whatever test bundle happened to be lying
    around. A stale bundle still produces a plausible looking table, which is
    the worst kind of wrong.
    """
    print("Building with coverage instrumentation ...")
    result = run([SWIFT, "build", "--enable-code-coverage", "--build-tests"],
                 cwd=REPO_ROOT)
    if result.returncode != 0:
        die("swift build failed with exit code %d" % result.returncode)


def run_swift_tests(profile_dir):
    """Run the XCTest suite, collecting profiles ourselves.

    Deliberately NOT `swift test --enable-code-coverage`. That flag makes
    SwiftPM merge the profiles itself when the run finishes, with the
    default failure mode, so a single truncated .profraw makes the whole
    command exit 1 even though every test passed.

    This package reliably produces a truncated one, and it is not a bug:
    testInPlaceWriteFailureLeavesOriginalUntouched runs the md binary under
    `ulimit -f 2` on purpose, to prove a failed write leaves the original
    file alone. The instrumented subprocess hits that file size limit while
    writing its own profile.

    The instrumentation comes from the build, not from this flag, so we skip
    the build, point the profiles where we want them, and do the merge
    ourselves further down. The exit code then means what it says: the tests
    passed, or they did not.
    """
    print("")
    print("Running swift test ...")
    import os
    env = dict(os.environ)
    env["LLVM_PROFILE_FILE"] = str(profile_dir / "swift-%p.profraw")
    result = run([SWIFT, "test", "--skip-build"], cwd=REPO_ROOT, env=env)
    if result.returncode != 0:
        sys.stderr.write("coverage: swift test failed with exit code %d. "
                         "The report below covers a failing suite.\n"
                         % result.returncode)
    return result.returncode


def run_cli_tests(profile_dir):
    """Run the CLI suite with every `md` process writing its own profile.

    LLVM_PROFILE_FILE must be absolute: the harness runs the binary from a
    scratch directory, so a relative path would scatter profiles across the
    filesystem. %p makes each process write to its own file, which matters
    because the suite runs the binary hundreds of times.
    """
    print("")
    print("Running cli-tests ...")
    if not CLI_TESTS.is_file():
        die("cannot find %s" % CLI_TESTS)

    import os
    env = dict(os.environ)
    env["LLVM_PROFILE_FILE"] = str(profile_dir / "md-%p.profraw")

    result = run([sys.executable, str(CLI_TESTS), "--no-build"],
                 cwd=REPO_ROOT, env=env)
    if result.returncode != 0:
        sys.stderr.write("coverage: cli-tests failed with exit code %d. "
                         "The report below covers a failing suite.\n"
                         % result.returncode)
    return result.returncode


def merge(sources, destination):
    """Merge every .profraw under the given directories into one .profdata.

    A test process that is killed, or that never gets far enough to write a
    full profile, leaves a truncated .profraw behind. failure-mode=all keeps
    those from sinking the whole merge: llvm-profdata warns about each one
    and merges the rest, and only errors if nothing at all could be read.
    """
    raws = []
    for source in sources:
        if source.is_dir():
            raws.extend(sorted(source.glob("*.profraw")))
    if not raws:
        die("no .profraw files were produced. Was the build instrumented?")

    argv = ([XCRUN, "llvm-profdata", "merge", "-sparse", "-failure-mode=all"]
            + [str(raw) for raw in raws] + ["-o", str(destination)])
    result = run(argv, capture=True)
    warnings = result.stderr.decode("utf-8", errors="replace").strip()
    if result.returncode != 0:
        die("llvm-profdata merge failed:\n%s" % warnings)
    if warnings:
        # Truncated profiles are common and harmless. Say how many were
        # skipped rather than hiding it.
        skipped = warnings.count("invalid instrumentation profile data")
        if skipped:
            print("  skipped %d truncated profile(s)" % skipped)
    return len(raws)


def report(profdata, binaries, options):
    # Only `llvm-cov show` writes annotated source, and only it understands
    # -format=html and -output-dir. `llvm-cov report` prints the summary
    # table and rejects both of those flags.
    annotated = options.show or options.html

    argv = [XCRUN, "llvm-cov", "show" if annotated else "report"]
    argv.append(str(binaries[0]))
    for extra in binaries[1:]:
        argv.extend(["-object", str(extra)])
    argv.append("-instr-profile=%s" % profdata)
    argv.append("-ignore-filename-regex=%s" % IGNORE_REGEX)

    if annotated:
        argv.append("-show-line-counts-or-regions")
    if options.html:
        argv.extend(["-format=html", "-output-dir=%s" % options.html])
    if not annotated:
        argv.append("-use-color=false")

    # --show streams pages of annotated source, so let it go straight to the
    # terminal. Everything else is captured, so that a failure can be
    # reported with the message llvm-cov actually gave.
    result = run(argv, capture=not options.show)
    if result.returncode != 0:
        message = ""
        if result.stderr:
            message = result.stderr.decode("utf-8", errors="replace").strip()
        die("llvm-cov failed:\n%s" % (message or "(no message)"))

    if options.html:
        print("HTML report written to %s/index.html" % options.html)
    elif not options.show:
        sys.stdout.write(result.stdout.decode("utf-8", errors="replace"))


def parse_options(argv):
    parser = argparse.ArgumentParser(
        prog="python3 scripts/coverage.py",
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
        allow_abbrev=False,
    )
    parser.add_argument(
        "--swift-only", action="store_true",
        help="measure only the swift test suite",
    )
    parser.add_argument(
        "--cli-only", action="store_true",
        help="measure only the cli-tests suite",
    )
    parser.add_argument(
        "--no-build", action="store_true",
        help="skip the instrumented build; it must already exist",
    )
    parser.add_argument(
        "--html", metavar="DIR",
        help="write a browsable HTML report to DIR instead of a table",
    )
    parser.add_argument(
        "--show", action="store_true",
        help="print annotated source showing which lines ran",
    )
    options = parser.parse_args(argv)
    if options.swift_only and options.cli_only:
        parser.error("--swift-only and --cli-only contradict each other")
    return options


def main(argv):
    options = parse_options(argv)

    want_swift = not options.cli_only
    want_cli = not options.swift_only

    if not options.no_build:
        build(options)

    build_dir = bin_path()
    swift_profiles = build_dir / "codecov-swift"
    cli_profiles = build_dir / "codecov-cli"

    # Clear only the directories this run will fill, so that --cli-only
    # reports the CLI suite alone rather than the CLI suite plus whatever
    # the last swift test run left behind.
    if want_swift:
        clear_profiles(swift_profiles)
    if want_cli:
        clear_profiles(cli_profiles)

    failed = 0
    if want_swift:
        failed |= run_swift_tests(swift_profiles)
    if want_cli:
        failed |= run_cli_tests(cli_profiles)

    sources = []
    if want_swift:
        sources.append(swift_profiles)
    if want_cli:
        sources.append(cli_profiles)

    profdata = build_dir / "codecov" / "merged.profdata"
    profdata.parent.mkdir(parents=True, exist_ok=True)

    print("")
    print("Merging coverage profiles ...")
    count = merge(sources, profdata)
    print("  merged %d profile(s)" % count)

    # Report against both binaries. The test bundle holds the code that
    # `swift test` ran, the md binary holds the code that cli-tests ran, and
    # a line is covered if either one reached it.
    binaries = []
    if want_swift:
        binaries.append(test_binary(build_dir))
    if want_cli:
        md_binary = build_dir / "md"
        if not md_binary.is_file():
            die("cannot find the md binary at %s" % md_binary)
        binaries.append(md_binary)

    print("")
    which = ("swift test" if options.swift_only else
             "cli-tests" if options.cli_only else
             "swift test + cli-tests")
    print("Line coverage of Sources/, measured by %s" % which)
    print("")
    report(profdata, binaries, options)

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
