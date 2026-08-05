//
//  FormatCommandRunTests.swift
//  md
//
//  Drives `md format` through run() rather than the static formatter, and
//  checks what survives a format round trip.
//

import XCTest
@testable import md

final class FormatCommandRunTests: XCTestCase {

    private var scratch: ScratchDirectory!

    override func setUpWithError() throws {
        scratch = try ScratchDirectory()
    }

    override func tearDownWithError() throws {
        scratch = nil
    }

    private func runFormat(
        _ arguments: [String] = [],
        on content: String
    ) async throws -> String {
        let path = try scratch.write(content, to: "document.md")
        let command = try FormatCommand.parse(arguments + ["--file", path])
        return try await StandardStream.capturingStandardOutput {
            try await command.run()
        }
    }

    // MARK: - run()

    func testFormatWritesTheNormalizedDocumentToStandardOutput() async throws {
        let output = try await runFormat(on: "#    Loose   heading\n\n\n\nBody.\n")
        XCTAssertEqual(output, "# Loose   heading\n\nBody.\n")
    }

    func testFormatLeavesTheSourceFileAlone() async throws {
        let content = "#    Loose   heading\n"
        let path = try scratch.write(content, to: "document.md")
        let command = try FormatCommand.parse(["--file", path])
        _ = try await StandardStream.capturingStandardOutput {
            try await command.run()
        }
        XCTAssertEqual(try scratch.read("document.md"), content)
    }

    func testFormatOfAnEmptyDocumentWritesNothing() async throws {
        let output = try await runFormat(on: "")
        XCTAssertEqual(output, "")
    }

    func testFormatKeepsFrontmatterVerbatim() async throws {
        let output = try await runFormat(
            on: "---\ntitle:   Hello\n---\n#    Heading\n"
        )
        XCTAssertEqual(output, "---\ntitle:   Hello\n---\n# Heading\n")
    }

    func testFormatConvertsFrontmatterOnRequest() async throws {
        let output = try await runFormat(
            ["--frontmatter", "toml"],
            on: "---\ntitle: Hello\n---\n#    Heading\n"
        )
        XCTAssertTrue(output.hasPrefix("+++\n"), "got: \(output)")
        XCTAssertTrue(output.hasSuffix("+++\n# Heading\n"), "got: \(output)")
    }

    func testFormatStripsEmptyFrontmatter() async throws {
        let output = try await runFormat(on: "---\n---\n#    Heading\n")
        XCTAssertEqual(output, "# Heading\n")
    }

    func testFormatReadsFromStandardInput() async throws {
        let command = try FormatCommand.parse(["--stdin"])
        let output = try await StandardStream.withStandardInput("#    Heading\n") {
            try await StandardStream.capturingStandardOutput {
                try await command.run()
            }
        }
        XCTAssertEqual(output, "# Heading\n")
    }

    func testFormatPreservesAByteOrderMark() async throws {
        let url = scratch.url.appendingPathComponent("bom.md")
        var source = Data([0xEF, 0xBB, 0xBF])
        source.append(contentsOf: Data("#    Heading\n".utf8))
        try source.write(to: url)

        let command = try FormatCommand.parse(["--file", url.path])
        let output = try await StandardStream.capturingStandardOutputData {
            try await command.run()
        }
        var expected = Data([0xEF, 0xBB, 0xBF])
        expected.append(contentsOf: Data("# Heading\n".utf8))
        XCTAssertEqual(output, expected)
    }

    func testFormatRejectsAnUnknownFrontmatterFormat() {
        XCTAssertThrowsError(
            try FormatCommand.parse(["--frontmatter", "xml", "--stdin"])
        )
    }

    // MARK: - Normalization the formatter is expected to perform

    func testFormatCollapsesRunsOfBlankLinesBetweenBlocks() async throws {
        let output = try await runFormat(on: "# A\n\n\n\n\n# B\n")
        XCTAssertEqual(output, "# A\n\n# B\n")
    }

    func testFormatRenumbersOrderedListsFromOne() async throws {
        let output = try await runFormat(on: "7. seven\n8. eight\n")
        XCTAssertEqual(output, "1. seven\n1. eight\n")
    }

    func testFormatRewritesAlternateBulletMarkersAsDashes() async throws {
        let output = try await runFormat(on: "* star\n* star\n")
        XCTAssertEqual(output, "- star\n- star\n")
    }

    func testFormatRewritesSetextHeadingsAsAtxHeadings() async throws {
        let output = try await runFormat(on: "Title\n=====\n")
        XCTAssertEqual(output, "# Title\n")
    }

    func testFormatIsIdempotentOnAlreadyNormalizedInput() async throws {
        let normalized = "# Title\n\nBody.\n\n- one\n- two\n"
        let output = try await runFormat(on: normalized)
        XCTAssertEqual(output, normalized)
    }

    // MARK: - What a format round trip loses

    func testFormatKeepsTheBreakInsideAWrappedParagraph() async throws {
        let output = try await runFormat(on: "line one\nline two\n")
        XCTAssertEqual(output, "line one\nline two\n")
    }

    func testFormatKeepsABlockquoteParagraphBreak() async throws {
        XCTExpectFailure("""
            A blockquote holding two paragraphs is flattened to a single run of \
            text, so md format writes "> AB". The two paragraphs should stay \
            apart. Same root cause as the parser-level blockquote test.
            """)
        let output = try await runFormat(on: "> A\n>\n> B\n")
        XCTAssertEqual(output, "> A\n> \n> B\n")
    }

    /// Fixed by `MarkdownEscaper`. See `EscapedMarkdownRoundTripTests` for the whole
    /// set of cases that `md format` must not change.
    func testFormatKeepsAnEscapedAsteriskEscaped() async throws {
        let output = try await runFormat(on: "an escaped \\*asterisk\\*\n")
        XCTAssertEqual(output, "an escaped \\*asterisk\\*\n")
    }

    func testFormatKeepsAListItemContinuationInsideItsItem() async throws {
        XCTExpectFailure("""
            A list item that wraps onto a second source line is rendered as \
            "- item one\\ncontinued\\n", where the continuation line no longer \
            starts inside the item. Re-parsing that output yields a list plus a \
            separate paragraph, so formatting twice changes the document \
            structure.
            """)
        let output = try await runFormat(on: "- item one\n  continued\n")
        XCTAssertEqual(output, "- item one continued\n")
    }

    func testFormatDropsHtmlBlocksEntirely() async throws {
        XCTExpectFailure("""
            MarkdownBlock has no case for raw HTML, so parseNode returns nil for \
            an html_block and md format deletes it. The <div> below should \
            survive the round trip.
            """)
        let output = try await runFormat(on: "Before.\n\n<div>x</div>\n\nAfter.\n")
        XCTAssertEqual(output, "Before.\n\n<div>x</div>\n\nAfter.\n")
    }
}
