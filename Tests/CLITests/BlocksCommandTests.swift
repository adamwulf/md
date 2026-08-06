//
//  BlocksCommandTests.swift
//  md
//
//  Exercises `md blocks` end to end: the listing mode, the count mode, the
//  slice mode, and every index the slice mode must reject.
//

import XCTest
@testable import md

final class BlocksCommandTests: XCTestCase {

    private var scratch: ScratchDirectory!

    override func setUpWithError() throws {
        scratch = try ScratchDirectory()
    }

    override func tearDownWithError() throws {
        scratch = nil
    }

    // MARK: - Helpers

    /// Writes `content` to a scratch file and runs `md blocks` against it,
    /// returning everything the command wrote to standard output.
    private func runBlocks(
        _ arguments: [String],
        on content: String
    ) async throws -> String {
        let path = try scratch.write(content, to: "document.md")
        let command = try BlocksCommand.parse(arguments + ["--file", path])
        return try await StandardStream.capturingStandardOutput {
            try await command.run()
        }
    }

    // MARK: - validate()

    /// The positional arguments fill start before end, so an end without a
    /// start is only reachable by clearing start after parsing.
    func testValidateRejectsEndWithoutStart() throws {
        let path = try scratch.write("# One\n", to: "document.md")
        var command = try BlocksCommand.parse(["--file", path, "2", "4"])
        command.start = nil
        XCTAssertThrowsError(try command.validate()) { error in
            XCTAssertEqual("\(error)", "Cannot specify end without start")
        }
    }

    func testValidateAcceptsStartWithoutEnd() throws {
        let path = try scratch.write("# One\n", to: "document.md")
        let command = try BlocksCommand.parse(["--file", path, "2"])
        XCTAssertNoThrow(try command.validate())
    }

    func testValidateAcceptsNeitherStartNorEnd() throws {
        let path = try scratch.write("# One\n", to: "document.md")
        let command = try BlocksCommand.parse(["--file", path])
        XCTAssertNoThrow(try command.validate())
    }

    // MARK: - --count

    func testCountPrintsNumberOfBlocks() async throws {
        let output = try await runBlocks(
            ["--count"],
            on: "# Title\n\nPara.\n\n## Section\n"
        )
        XCTAssertEqual(output, "3\n")
    }

    func testCountPrintsZeroForEmptyDocument() async throws {
        let output = try await runBlocks(["--count"], on: "")
        XCTAssertEqual(output, "0\n")
    }

    func testCountIgnoresFrontmatterBlocks() async throws {
        let output = try await runBlocks(
            ["--count"],
            on: "---\ntitle: A\n---\n\n# Heading\n"
        )
        XCTAssertEqual(output, "1\n")
    }

    func testCountTakesPrecedenceOverStartIndex() async throws {
        let output = try await runBlocks(
            ["--count", "1"],
            on: "# Title\n\nPara.\n"
        )
        XCTAssertEqual(output, "2\n")
    }

    // MARK: - Listing mode summaries

    func testListingSummarizesHeadingWithLevelAndText() async throws {
        let output = try await runBlocks([], on: "### Deep\n")
        XCTAssertEqual(output, "[1] heading(3) L1: Deep\n")
    }

    func testListingSummarizesParagraphWithLineRange() async throws {
        let output = try await runBlocks([], on: "One line\nsecond line\n")
        XCTAssertEqual(output, "[1] paragraph L1-2\n")
    }

    func testListingSummarizesFencedCodeBlockWithLanguage() async throws {
        let output = try await runBlocks([], on: "```swift\nlet x = 1\n```\n")
        XCTAssertEqual(output, "[1] code(swift) L1-3\n")
    }

    /// `summary(of:)` falls back to "none" only when the language is nil, but
    /// `MarkdownParser` reports an empty string for an unlabelled fence, so the
    /// label the user sees is `code()`.
    func testListingSummarizesFencedCodeBlockWithoutLanguageAsEmptyLabel() async throws {
        let output = try await runBlocks([], on: "```\nplain\n```\n")
        XCTAssertEqual(output, "[1] code() L1-3\n")
    }

    func testListingSummarizesUnorderedListWithItemCount() async throws {
        let output = try await runBlocks([], on: "- a\n- b\n- c\n")
        XCTAssertEqual(output, "[1] unordered list(3 items) L1-3\n")
    }

    func testListingSummarizesOrderedListWithItemCount() async throws {
        let output = try await runBlocks([], on: "1. a\n2. b\n")
        XCTAssertEqual(output, "[1] ordered list(2 items) L1-2\n")
    }

    func testListingSummarizesBlockquoteWithLineRange() async throws {
        let output = try await runBlocks([], on: "> quoted\n")
        XCTAssertEqual(output, "[1] blockquote L1-1\n")
    }

    func testListingSummarizesThematicBreakWithSingleLine() async throws {
        let output = try await runBlocks([], on: "Above\n\n---\n\nBelow\n")
        XCTAssertEqual(
            output,
            "[1] paragraph L1-1\n[2] thematic_break L3\n[3] paragraph L5-5\n"
        )
    }

    func testListingSummarizesHTMLWithItsLineRange() async throws {
        let output = try await runBlocks([], on: "<div>\nraw\n</div>\n")
        XCTAssertEqual(output, "[1] html L1-3\n")
    }

    func testSlicesIncludeTheClosingLineOfEveryDelimiterTerminatedHtmlForm() async throws {
        let htmlBlocks = [
            "<script>\nscript body\n</script>",
            "<!--\ncomment body\n-->",
            "<?target\nprocessing body\n?>",
            "<!DOCTYPE\ndeclaration body>",
            "<![CDATA[\ncdata body\n]]>"
        ]

        for html in htmlBlocks {
            let output = try await runBlocks(
                ["2"],
                on: "Before.\n\n\(html)\n\nAfter.\n"
            )
            XCTAssertEqual(output, "\(html)\n", "for \(html)")
        }
    }

    func testSliceStopsAtAUnicodeLineSeparatorInsideHtml() async throws {
        let html = "<!-- alpha\u{2028}omega -->"
        let output = try await runBlocks(["1"], on: "\(html)\nAfter.\n")
        XCTAssertEqual(output, "\(html)\n")
    }

    func testSlicesKeepLegalLeadingIndentationOnHtmlAndLists() async throws {
        let html = "   <script>\nx\n</script>"
        let htmlOutput = try await runBlocks(
            ["1"],
            on: "\(html)\n\nAfter.\n"
        )
        XCTAssertEqual(htmlOutput, "\(html)\n")

        let list = "   - alpha\n   - beta"
        let listOutput = try await runBlocks(
            ["1"],
            on: "\(list)\n\nAfter.\n"
        )
        XCTAssertEqual(listOutput, "\(list)\n")
    }

    func testListingSummarizesTableWithRowCount() async throws {
        let output = try await runBlocks(
            [],
            on: "| A | B |\n| --- | --- |\n| 1 | 2 |\n"
        )
        XCTAssertEqual(output, "[1] table(2 rows) L1-3\n")
    }

    func testListingNumbersBlocksFromOne() async throws {
        let output = try await runBlocks(
            [],
            on: "# Title\n\nPara.\n\n## Section\n"
        )
        XCTAssertEqual(
            output,
            "[1] heading(1) L1: Title\n[2] paragraph L3-3\n[3] heading(2) L5: Section\n"
        )
    }

    func testListingPrintsNothingForEmptyDocument() async throws {
        let output = try await runBlocks([], on: "")
        XCTAssertEqual(output, "")
    }

    func testListingReportsLineNumbersOfOriginalDocumentWithFrontmatter() async throws {
        let output = try await runBlocks(
            [],
            on: "---\ntitle: A\n---\n\n# Heading\n"
        )
        XCTAssertEqual(output, "[1] heading(1) L5: Heading\n")
    }

    // MARK: - Slice mode

    func testSingleIndexPrintsThatBlockVerbatim() async throws {
        let output = try await runBlocks(
            ["2"],
            on: "# Title\n\nPara.\n\n## Section\n"
        )
        XCTAssertEqual(output, "Para.\n")
    }

    func testEndDefaultsToStartWhenOmitted() async throws {
        let single = try await runBlocks(["1"], on: "# One\n\n# Two\n")
        let explicit = try await runBlocks(["1", "1"], on: "# One\n\n# Two\n")
        XCTAssertEqual(single, "# One\n")
        XCTAssertEqual(single, explicit)
    }

    func testRangeSeparatesBlocksWithABlankLine() async throws {
        let output = try await runBlocks(["1", "2"], on: "# One\n\n# Two\n")
        XCTAssertEqual(output, "# One\n\n# Two\n")
    }

    func testSliceEmitsSourceBytesRatherThanNormalizedText() async throws {
        let output = try await runBlocks(["1"], on: "#    Loosely   spaced\n")
        XCTAssertEqual(output, "#    Loosely   spaced\n")
    }

    func testSlicePreservesMultiByteCharacters() async throws {
        let output = try await runBlocks(["2"], on: "# Título\n\nCafé 🌍 déjà\n")
        XCTAssertEqual(output, "Café 🌍 déjà\n")
    }

    func testSliceSkipsFrontmatterWhenIndexingBlocks() async throws {
        let output = try await runBlocks(
            ["1"],
            on: "---\ntitle: A\n---\n\n# Heading\n"
        )
        XCTAssertEqual(output, "# Heading\n")
    }

    // MARK: - Slice mode rejects out-of-range indices

    func testStartBelowOneIsRejected() async {
        await XCTAssertThrowsErrorMessage(
            "Block indices must be in range 1...2, got 0...0"
        ) {
            _ = try await self.runBlocks(["0"], on: "# One\n\n# Two\n")
        }
    }

    func testNegativeStartIsRejected() async throws {
        let path = try scratch.write("# One\n\n# Two\n", to: "document.md")
        // `--` keeps ArgumentParser from reading "-1" as a short option name.
        let command = try BlocksCommand.parse(["--file", path, "--", "-1"])
        await XCTAssertThrowsErrorMessage(
            "Block indices must be in range 1...2, got -1...-1"
        ) {
            try await command.run()
        }
    }

    func testEndBeforeStartIsRejected() async {
        await XCTAssertThrowsErrorMessage(
            "Block indices must be in range 1...2, got 2...1"
        ) {
            _ = try await self.runBlocks(["2", "1"], on: "# One\n\n# Two\n")
        }
    }

    func testEndPastLastBlockIsRejected() async {
        await XCTAssertThrowsErrorMessage(
            "Block indices must be in range 1...2, got 1...3"
        ) {
            _ = try await self.runBlocks(["1", "3"], on: "# One\n\n# Two\n")
        }
    }

    func testAnyIndexIsRejectedForAnEmptyDocument() async {
        await XCTAssertThrowsErrorMessage(
            "Block indices must be in range 1...0, got 1...1"
        ) {
            _ = try await self.runBlocks(["1"], on: "")
        }
    }

    func testLastBlockIndexIsAccepted() async throws {
        let output = try await runBlocks(["2"], on: "# One\n\n# Two\n")
        XCTAssertEqual(output, "# Two\n")
    }

    // MARK: - Input selection

    func testReadsFromStandardInputWhenAskedTo() async throws {
        let command = try BlocksCommand.parse(["--count", "--stdin"])
        let output = try await StandardStream.withStandardInput("# One\n\n# Two\n") {
            try await StandardStream.capturingStandardOutput {
                try await command.run()
            }
        }
        XCTAssertEqual(output, "2\n")
    }

    func testMissingFileReportsAReadFailure() async {
        let missing = scratch.url.appendingPathComponent("absent.md").path
        let command = try? BlocksCommand.parse(["--count", "--file", missing])
        XCTAssertNotNil(command)
        do {
            try await command?.run()
            XCTFail("Expected reading a nonexistent file to throw")
        } catch {
            XCTAssertTrue(
                "\(error)".contains("absent.md"),
                "error should name the missing file, got: \(error)"
            )
        }
    }
}
