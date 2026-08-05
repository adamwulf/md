//
//  LinesCommandTests.swift
//  md
//
//  Exercises `md lines`: the numbered listing and its padding, the count mode,
//  the slice mode, and every line number the slice mode must reject.
//

import XCTest
@testable import md

final class LinesCommandTests: XCTestCase {

    private var scratch: ScratchDirectory!

    override func setUpWithError() throws {
        scratch = try ScratchDirectory()
    }

    override func tearDownWithError() throws {
        scratch = nil
    }

    // MARK: - Helpers

    private func runLines(
        _ arguments: [String],
        on content: String
    ) async throws -> String {
        let path = try scratch.write(content, to: "document.md")
        let command = try LinesCommand.parse(arguments + ["--file", path])
        return try await StandardStream.capturingStandardOutput {
            try await command.run()
        }
    }

    // MARK: - validate()

    /// The positional arguments fill start before end, so an end without a
    /// start is only reachable by clearing start after parsing.
    func testValidateRejectsEndWithoutStart() throws {
        let path = try scratch.write("one\n", to: "document.md")
        var command = try LinesCommand.parse(["--file", path, "3", "9"])
        command.start = nil
        XCTAssertThrowsError(try command.validate()) { error in
            XCTAssertEqual("\(error)", "Cannot specify end without start")
        }
    }

    func testValidateAcceptsStartWithoutEnd() throws {
        let path = try scratch.write("one\n", to: "document.md")
        let command = try LinesCommand.parse(["--file", path, "3"])
        XCTAssertNoThrow(try command.validate())
    }

    func testValidateAcceptsNeitherStartNorEnd() throws {
        let path = try scratch.write("one\n", to: "document.md")
        let command = try LinesCommand.parse(["--file", path])
        XCTAssertNoThrow(try command.validate())
    }

    // MARK: - --count

    func testCountPrintsNumberOfLines() async throws {
        let output = try await runLines(["--count"], on: "one\ntwo\nthree")
        XCTAssertEqual(output, "3\n")
    }

    func testTrailingNewlineTerminatesTheLastLineWithoutAddingAnother() async throws {
        let output = try await runLines(["--count"], on: "one\ntwo\nthree\n")
        XCTAssertEqual(output, "3\n")
    }

    func testCountOfEmptyDocumentIsZero() async throws {
        let output = try await runLines(["--count"], on: "")
        XCTAssertEqual(output, "0\n")
    }

    func testCountTreatsLoneCarriageReturnsAsLineEndings() async throws {
        let output = try await runLines(["--count"], on: "one\rtwo\r")
        XCTAssertEqual(output, "2\n")
    }

    func testCountKeepsABlankLineBeforeTheFinalNewline() async throws {
        let output = try await runLines(["--count"], on: "one\n\n")
        XCTAssertEqual(output, "2\n")
    }

    func testOneNewlineIsOneBlankLine() async throws {
        let output = try await runLines(["--count"], on: "\n")
        XCTAssertEqual(output, "1\n")
    }

    func testCountTakesPrecedenceOverStartLine() async throws {
        let output = try await runLines(["--count", "1"], on: "one\ntwo")
        XCTAssertEqual(output, "2\n")
    }

    // MARK: - Listing mode

    func testListingPrintsEachLineAfterItsNumber() async throws {
        let output = try await runLines([], on: "alpha\nbeta")
        XCTAssertEqual(output, "1  alpha\n2  beta\n")
    }

    func testListingDoesNotInventALineAfterATrailingNewline() async throws {
        let output = try await runLines([], on: "alpha\nbeta\n")
        XCTAssertEqual(output, "1  alpha\n2  beta\n")
    }

    func testListingRightAlignsNumbersToTheWidestLineNumber() async throws {
        let content = (1...10).map { "line \($0)" }.joined(separator: "\n")
        let output = try await runLines([], on: content)
        let printed = output.split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertEqual(printed.first, " 1  line 1")
        XCTAssertEqual(printed[8], " 9  line 9")
        XCTAssertEqual(printed[9], "10  line 10")
    }

    func testListingPrintsNothingForAnEmptyDocument() async throws {
        let output = try await runLines([], on: "")
        XCTAssertEqual(output, "")
    }

    func testListingKeepsBlankLinesInPlace() async throws {
        let output = try await runLines([], on: "alpha\n\nbeta")
        XCTAssertEqual(output, "1  alpha\n2  \n3  beta\n")
    }

    func testListingKeepsLoneCarriageReturnsObservable() async throws {
        let output = try await runLines([], on: "alpha\rbeta\r")
        XCTAssertEqual(output, "1  alpha\r\n2  beta\r\n")
    }

    /// Lines are raw source, so frontmatter delimiters are listed like any
    /// other line — unlike `md blocks`, which skips them.
    func testListingIncludesFrontmatterLines() async throws {
        let output = try await runLines([], on: "---\ntitle: A\n---\n# H")
        XCTAssertEqual(output, "1  ---\n2  title: A\n3  ---\n4  # H\n")
    }

    // MARK: - Slice mode

    func testSingleLineNumberPrintsThatLine() async throws {
        let output = try await runLines(["2"], on: "one\ntwo\nthree")
        XCTAssertEqual(output, "two\n")
    }

    func testEndDefaultsToStartWhenOmitted() async throws {
        let single = try await runLines(["2"], on: "one\ntwo\nthree")
        let explicit = try await runLines(["2", "2"], on: "one\ntwo\nthree")
        XCTAssertEqual(single, explicit)
    }

    func testRangePrintsLinesWithoutNumbersOrSeparators() async throws {
        let output = try await runLines(["1", "3"], on: "one\ntwo\nthree")
        XCTAssertEqual(output, "one\ntwo\nthree\n")
    }

    func testSlicePreservesLeadingWhitespace() async throws {
        let output = try await runLines(["2"], on: "one\n    indented\nthree")
        XCTAssertEqual(output, "    indented\n")
    }

    func testLastLineNumberIsAccepted() async throws {
        let output = try await runLines(["3"], on: "one\ntwo\nthree")
        XCTAssertEqual(output, "three\n")
    }

    // MARK: - Slice mode rejects out-of-range line numbers

    func testStartBelowOneIsRejected() async {
        await XCTAssertThrowsErrorMessage(
            "Line numbers must be in range 1...3, got 0...0"
        ) {
            _ = try await self.runLines(["0"], on: "one\ntwo\nthree")
        }
    }

    func testEndBeforeStartIsRejected() async {
        await XCTAssertThrowsErrorMessage(
            "Line numbers must be in range 1...3, got 3...2"
        ) {
            _ = try await self.runLines(["3", "2"], on: "one\ntwo\nthree")
        }
    }

    func testEndPastLastLineIsRejected() async {
        await XCTAssertThrowsErrorMessage(
            "Line numbers must be in range 1...3, got 1...4"
        ) {
            _ = try await self.runLines(["1", "4"], on: "one\ntwo\nthree")
        }
    }

    func testLineAfterATrailingNewlineIsRejected() async {
        await XCTAssertThrowsErrorMessage(
            "Line numbers must be in range 1...3, got 4...4"
        ) {
            _ = try await self.runLines(["4"], on: "one\ntwo\nthree\n")
        }
    }

    // MARK: - Input selection

    func testReadsFromStandardInputWhenAskedTo() async throws {
        let command = try LinesCommand.parse(["--count", "--stdin"])
        let output = try await StandardStream.withStandardInput("a\nb\nc") {
            try await StandardStream.capturingStandardOutput {
                try await command.run()
            }
        }
        XCTAssertEqual(output, "3\n")
    }
}
