//
//  TocCommandTests.swift
//  md
//
//  Exercises `md toc`: the mutually exclusive --blocks/--lines flags, the
//  dot-fill layout, the right-aligned number column, and the EOF marker.
//

import XCTest
@testable import md

final class TocCommandTests: XCTestCase {

    private var scratch: ScratchDirectory!

    override func setUpWithError() throws {
        scratch = try ScratchDirectory()
    }

    override func tearDownWithError() throws {
        scratch = nil
    }

    // MARK: - Helpers

    private func runToc(
        _ arguments: [String],
        on content: String
    ) async throws -> String {
        let path = try scratch.write(content, to: "document.md")
        let command = try TocCommand.parse(arguments + ["--file", path])
        return try await StandardStream.capturingStandardOutput {
            try await command.run()
        }
    }

    private func dots(_ count: Int) -> String {
        String(repeating: ".", count: count)
    }

    private let sample = "# Title\n\nPara.\n\n## Section\n\nMore.\n"

    // MARK: - validate()

    func testValidateRejectsBothBlocksAndLines() throws {
        let path = try scratch.write(sample, to: "document.md")
        XCTAssertThrowsError(
            try TocCommand.parse(["--blocks", "--lines", "--file", path])
        ) { error in
            XCTAssertEqual(
                TocCommand.message(for: error),
                "Cannot specify both --blocks and --lines"
            )
        }
    }

    func testValidateRejectsNeitherBlocksNorLines() throws {
        let path = try scratch.write(sample, to: "document.md")
        XCTAssertThrowsError(try TocCommand.parse(["--file", path])) { error in
            XCTAssertEqual(
                TocCommand.message(for: error),
                "Must specify either --blocks or --lines"
            )
        }
    }

    func testValidateAcceptsLinesAlone() throws {
        let path = try scratch.write(sample, to: "document.md")
        XCTAssertNoThrow(try TocCommand.parse(["--lines", "--file", path]))
    }

    func testValidateAcceptsBlocksAlone() throws {
        let path = try scratch.write(sample, to: "document.md")
        XCTAssertNoThrow(try TocCommand.parse(["--blocks", "--file", path]))
    }

    // MARK: - --lines

    func testLinesModeNumbersEachHeadingByItsSourceLine() async throws {
        let output = try await runToc(["--lines"], on: sample)
        XCTAssertEqual(
            output,
            "Title \(dots(52)) 1\n"
                + "  Section \(dots(48)) 5\n"
                + "EOF \(dots(54)) 8\n"
        )
    }

    func testLinesModeEndsWithTheTotalLineCount() async throws {
        let output = try await runToc(["--lines"], on: "# Only\n")
        XCTAssertEqual(
            output,
            "Only \(dots(53)) 1\n"
                + "EOF \(dots(54)) 2\n"
        )
    }

    // MARK: - --blocks

    func testBlocksModeNumbersEachHeadingByItsBlockIndex() async throws {
        let output = try await runToc(["--blocks"], on: sample)
        XCTAssertEqual(
            output,
            "Title \(dots(52)) 1\n"
                + "  Section \(dots(48)) 3\n"
                + "EOF \(dots(54)) 4\n"
        )
    }

    func testBlocksModeEndsWithTheTotalBlockCount() async throws {
        let output = try await runToc(["--blocks"], on: "# Only\n")
        XCTAssertEqual(
            output,
            "Only \(dots(53)) 1\n"
                + "EOF \(dots(54)) 1\n"
        )
    }

    // MARK: - Indentation

    func testHeadingIndentGrowsByTwoSpacesPerLevel() async throws {
        let content = "# L1\n\n## L2\n\n### L3\n"
        let output = try await runToc(["--blocks"], on: content)
        let printed = output.split(separator: "\n").map(String.init)
        XCTAssertEqual(printed.count, 4)
        XCTAssertTrue(printed[0].hasPrefix("L1 "), "got: \(printed[0])")
        XCTAssertTrue(printed[1].hasPrefix("  L2 "), "got: \(printed[1])")
        XCTAssertTrue(printed[2].hasPrefix("    L3 "), "got: \(printed[2])")
    }

    // MARK: - Number column width

    func testNumberColumnIsPaddedToTheWidestLineNumber() async throws {
        let content = "# One\n\nx\n\nx\n\nx\n\nx\n\n## Two\n"
        let output = try await runToc(["--lines"], on: content)
        XCTAssertEqual(
            output,
            "One \(dots(53))  1\n"
                + "  Two \(dots(51)) 11\n"
                + "EOF \(dots(53)) 12\n"
        )
    }

    // MARK: - Dot fill boundary

    func testDotFillNeverShrinksBelowOneDot() async throws {
        let heading = String(repeating: "A", count: 60)
        let output = try await runToc(["--lines"], on: "# \(heading)\n")
        XCTAssertEqual(
            output,
            "\(heading) . 1\n"
                + "EOF \(dots(54)) 2\n"
        )
    }

    // MARK: - Documents without headings

    func testDocumentWithoutHeadingsPrintsOnlyTheEOFLine() async throws {
        let output = try await runToc(["--lines"], on: "Just a paragraph.\n")
        XCTAssertEqual(output, "EOF \(dots(54)) 2\n")
    }

    func testEmptyDocumentPrintsEOFAtLineOne() async throws {
        let output = try await runToc(["--lines"], on: "")
        XCTAssertEqual(output, "EOF \(dots(54)) 1\n")
    }

    func testEmptyDocumentPrintsEOFAtBlockZero() async throws {
        let output = try await runToc(["--blocks"], on: "")
        XCTAssertEqual(output, "EOF \(dots(54)) 0\n")
    }

    // MARK: - Frontmatter

    func testFrontmatterIsExcludedFromBlockNumbering() async throws {
        let content = "---\ntitle: A\n---\n\n# Heading\n"
        let output = try await runToc(["--blocks"], on: content)
        XCTAssertEqual(
            output,
            "Heading \(dots(50)) 1\n"
                + "EOF \(dots(54)) 1\n"
        )
    }

    func testFrontmatterLinesStillCountTowardHeadingLineNumbers() async throws {
        let content = "---\ntitle: A\n---\n\n# Heading\n"
        let output = try await runToc(["--lines"], on: content)
        XCTAssertEqual(
            output,
            "Heading \(dots(50)) 5\n"
                + "EOF \(dots(54)) 6\n"
        )
    }

    // MARK: - Input selection

    func testReadsFromStandardInputWhenAskedTo() async throws {
        let command = try TocCommand.parse(["--lines", "--stdin"])
        let output = try await StandardStream.withStandardInput("# Only\n") {
            try await StandardStream.capturingStandardOutput {
                try await command.run()
            }
        }
        XCTAssertEqual(
            output,
            "Only \(dots(53)) 1\n"
                + "EOF \(dots(54)) 2\n"
        )
    }
}
