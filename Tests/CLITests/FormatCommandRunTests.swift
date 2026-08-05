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

    func testFormatRefusesToConvertANullValueToTOML() async throws {
        let path = try scratch.write(
            "---\npublished: null\n---\nBody\n",
            to: "document.md"
        )
        let command = try FormatCommand.parse([
            "--frontmatter", "toml", "--file", path,
        ])

        do {
            try await command.run()
            XCTFail("Expected TOML conversion to reject null")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "TOML cannot represent the null value at key path published"
            )
        }
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

    /// A hard line break is two or more trailing spaces before a newline. It is not a
    /// blank line: it holds one paragraph together and breaks the line inside it. A
    /// blank line divides two paragraphs, and `md format` handles that correctly.
    func testFormatKeepsAHardLineBreakWrittenWithTwoSpaces() async throws {
        let output = try await runFormat(on: "line one  \nline two\n")
        XCTAssertFalse(output.contains("oneline"), "the hard break was dropped: \(output.debugDescription)")
        XCTAssertEqual(output, "line one\\\nline two\n")
    }

    /// The backslash spelling of the same break. A backslash at the end of a line is a
    /// hard line break, exactly like two trailing spaces.
    func testFormatKeepsAHardLineBreakWrittenWithABackslash() async throws {
        let output = try await runFormat(on: "line one\\\nline two\n")
        XCTAssertFalse(output.contains("oneline"), "the hard break was dropped: \(output.debugDescription)")
        XCTAssertEqual(output, "line one\\\nline two\n")
    }

    /// `md format` writes the backslash spelling, thus its own output goes through a
    /// second format with no change. A break that changed spelling on each pass would
    /// make the command unsafe to run more than once.
    func testFormatIsIdempotentOnAHardLineBreak() async throws {
        let once = try await runFormat(on: "line one  \nline two\n")
        let twice = try await runFormat(on: once)
        XCTAssertEqual(twice, once)
    }

    /// The break dies wherever it sits, not only at the end of the paragraph. Here the
    /// soft break of the first two lines survives and only the hard break is lost.
    /// The two kinds of break stand side by side here, and each keeps its own spelling:
    /// the soft break stays a bare newline, and the hard break takes the backslash.
    func testFormatKeepsAHardLineBreakThatFollowsASoftOne() async throws {
        let output = try await runFormat(on: "line one\nline two  \nline three\n")
        XCTAssertFalse(output.contains("twoline"), "the hard break was dropped: \(output.debugDescription)")
        XCTAssertEqual(output, "line one\nline two\\\nline three\n")
    }

    /// A blank line is not a hard break. This one passes, and it is here so that the
    /// two are not confused: `md format` divides two paragraphs correctly.
    func testFormatKeepsTwoParagraphsApart() async throws {
        let output = try await runFormat(on: "para one\n\npara two\n")
        XCTAssertEqual(output, "para one\n\npara two\n")
    }

    /// A setext heading written with a hard break loses the same way, and a heading is
    /// one line, thus the two lines belong together with a space between them.
    func testFormatKeepsAHardLineBreakInsideASetextHeading() async throws {
        let output = try await runFormat(on: "alpha  \nbravo\n=====\n")
        XCTAssertEqual(output, "# alpha bravo\n")
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

    /// The continuation is indented under the item's content. A second format
    /// pass produces the same single-item document, so the old failure marker
    /// described an incorrect expectation rather than a formatter defect.
    func testFormatKeepsAListItemContinuationInsideItsItem() async throws {
        let output = try await runFormat(on: "- item one\n  continued\n")
        XCTAssertEqual(output, "- item one\n  continued\n")
        let secondPass = try await runFormat(on: output)
        XCTAssertEqual(secondPass, output)
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
