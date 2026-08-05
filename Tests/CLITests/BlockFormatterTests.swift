//
//  BlockFormatterTests.swift
//  md
//
//  Created by Adam Wulf on 4/12/26.
//

import XCTest
@testable import md
@testable import MarkdownKit

final class BlockFormatterTests: XCTestCase {

    let parser = MarkdownParser()

    func testFormatHeading() {
        let blocks = parser.parse("# Title")
        let output = BlockFormatter.format(blocks)
        XCTAssertEqual(output, "# Title\n")
    }

    func testFormatParagraph() {
        let blocks = parser.parse("Hello world.")
        let output = BlockFormatter.format(blocks)
        XCTAssertEqual(output, "Hello world.\n")
    }

    func testFormatMultilineSetextHeadingStaysOneBlock() {
        let source = "Heading one\nHeading two\n==========="
        let output = BlockFormatter.format(parser.parse(source))
        XCTAssertEqual(output, "# Heading one Heading two\n")
        // The formatted heading must parse again as one heading, not as a heading
        // plus a stray paragraph, or an edit of a later block would move it.
        XCTAssertEqual(parser.parse(output).count, 1)
    }

    func testFormatMultilineParagraphNormalizesBlankLinesBetweenParagraphs() {
        // The last line of a paragraph does not get a blank line of its own. One blank
        // line between two paragraphs is enough, thus "\n\n\n" becomes "\n\n".
        let blocks = parser.parse("line1\nline2\nline3\n\n\npara2")
        let output = BlockFormatter.format(blocks)
        XCTAssertEqual(output, "line1\nline2\nline3\n\npara2\n")
    }

    func testFormatMultilineParagraphIsIdempotent() {
        let source = "line1\nline2\nline3\n\n\npara2"
        let firstPass = BlockFormatter.format(parser.parse(source))
        let secondPass = BlockFormatter.format(parser.parse(firstPass))
        XCTAssertEqual(secondPass, firstPass)
    }

    /// KNOWN FAILURE, kept as documentation for a later fix.
    ///
    /// An indent of four or more spaces makes a markdown marker inert, thus the marker
    /// stays part of the paragraph text. The formatter writes each line of that text
    /// without the indent, thus the marker becomes live markdown and the one paragraph
    /// divides into more than one block, or becomes a heading.
    ///
    /// The lost indent came before the soft-break change, but this failure did not:
    /// while the two lines ran together, the marker stayed in the middle of a line and
    /// did nothing.
    ///
    /// A full fix needs escape logic, or an indent, in the formatter, which is larger
    /// than the soft break fix. Remove the `XCTExpectFailure` when the fix is in.
    func testFormatParagraphWithInertMarkerOnContinuationLine() {
        for source in ["line1\n    ---", "line1\n    - x", "line1\n    1) x"] {
            XCTAssertEqual(parser.parse(source).count, 1, "Expected one paragraph: \(source.debugDescription)")
            let firstPass = BlockFormatter.format(parser.parse(source))
            let secondPass = BlockFormatter.format(parser.parse(firstPass))
            XCTExpectFailure("An inert marker becomes live markdown after format") {
                XCTAssertEqual(secondPass, firstPass, "source: \(source.debugDescription)")
            }
        }
    }

    func testFormatMultilineBlockquote() {
        let blocks = parser.parse("> line1\n> line2")
        let output = BlockFormatter.format(blocks)
        XCTAssertEqual(output, "> line1\n> line2\n")
    }

    func testFormatMultilineParagraphKeepsUnicodeAndNormalizesCRLF() {
        // A file with CRLF endings gives LF in the written block, which agrees with
        // every other line that BlockFormatter writes. No "\r" is left behind.
        let blocks = parser.parse("héllo wörld\r\n🎉 second line\r\n")
        let output = BlockFormatter.format(blocks)
        XCTAssertEqual(output, "héllo wörld\n🎉 second line\n")
        XCTAssertFalse(output.contains("\r"))
    }

    /// A continuation line that looks like markdown must not become a new block when
    /// the paragraph is written back. These four cannot cut a paragraph in two, thus
    /// they stay in the paragraph after a round trip.
    func testFormatMultilineParagraphWithMarkdownLookalikeContinuationLines() {
        for source in [
            "foo\n2. not a list",
            "foo\n| a | b |",
            "foo\n[bar]: /url",
            "foo\n<https://example.com>",
        ] {
            let blocks = parser.parse(source)
            XCTAssertEqual(blocks.count, 1, "expected one block for \(source.debugDescription)")
            let output = BlockFormatter.format(blocks)
            XCTAssertEqual(
                parser.parse(output).count,
                1,
                "block count moved for \(source.debugDescription): \(output.debugDescription)"
            )
            XCTAssertEqual(BlockFormatter.format(parser.parse(output)), output)
        }
    }

    func testFormatNestedListWithMultilineItemsIsIdempotent() {
        let source = "- a\n  a2\n    - b\n      b2\n        - c\n          c2"
        let firstPass = BlockFormatter.format(parser.parse(source))
        let secondPass = BlockFormatter.format(parser.parse(firstPass))
        XCTAssertEqual(secondPass, firstPass)

        // The items must survive the round trip with their nesting and their text.
        if case .list(let items, _, _, _, _) = parser.parse(firstPass)[0] {
            XCTAssertEqual(items.map { $0.text }, ["a\na2", "b\nb2", "c\nc2"])
            XCTAssertEqual(items.map { $0.indentLevel }, [0, 1, 2])
        } else {
            XCTFail("Expected list block")
        }
    }

    func testFormatCodeBlock() {
        let blocks = parser.parse("```swift\nlet x = 1\n```")
        let output = BlockFormatter.format(blocks)
        XCTAssertEqual(output, "```swift\nlet x = 1\n```\n")
    }

    func testFormatUnorderedList() {
        let blocks = parser.parse("- A\n- B")
        let output = BlockFormatter.format(blocks)
        XCTAssertEqual(output, "- A\n- B\n")
    }

    func testFormatOrderedList() {
        let blocks = parser.parse("1. First\n2. Second")
        let output = BlockFormatter.format(blocks)
        XCTAssertEqual(output, "1. First\n1. Second\n")
    }

    func testFormatBlockquote() {
        let blocks = parser.parse("> Quote text")
        let output = BlockFormatter.format(blocks)
        XCTAssertEqual(output, "> Quote text\n")
    }

    func testFormatThematicBreak() {
        let blocks = parser.parse("Above\n\n---\n\nBelow")
        let output = BlockFormatter.format(blocks[1...1].map { $0 })
        XCTAssertEqual(output, "---\n")
    }

    func testFormatMultipleBlocks() {
        let blocks = parser.parse("# Title\n\nParagraph.")
        let output = BlockFormatter.format(blocks)
        XCTAssertEqual(output, "# Title\n\nParagraph.\n")
    }

    func testFormatSingleBlock() {
        let blocks = parser.parse("# Title\n\nParagraph.")
        let output = BlockFormatter.format(blocks[0])
        XCTAssertEqual(output, "# Title\n")
    }

    func testFormatEmptyArray() {
        let output = BlockFormatter.format([])
        XCTAssertEqual(output, "")
    }

    func testInsertAfterFirstBlock() {
        let markdown = "# Title\n\nParagraph."
        let blocks = parser.parse(markdown)
        let newBlocks = parser.parse("New content.")

        var result = ""
        for (i, block) in blocks.enumerated() {
            if i > 0 { result += "\n" }
            result += BlockFormatter.format(block)
            if i + 1 == 1 {
                result += "\n" + BlockFormatter.format(newBlocks)
            }
        }

        XCTAssertTrue(result.contains("# Title\n"))
        XCTAssertTrue(result.contains("New content.\n"))
        XCTAssertTrue(result.contains("Paragraph.\n"))

        // Verify order: Title comes before New content, which comes before Paragraph
        let titleRange = result.range(of: "# Title")!
        let newRange = result.range(of: "New content.")!
        let paraRange = result.range(of: "Paragraph.")!
        XCTAssertTrue(titleRange.lowerBound < newRange.lowerBound)
        XCTAssertTrue(newRange.lowerBound < paraRange.lowerBound)
    }

    func testInsertBeforeLastBlock() {
        let markdown = "# Title\n\nParagraph."
        let blocks = parser.parse(markdown)
        let newBlocks = parser.parse("Inserted.")

        var result = ""
        for (i, block) in blocks.enumerated() {
            if i + 1 == 2 {
                if i > 0 { result += "\n" }
                result += BlockFormatter.format(newBlocks) + "\n"
                result += BlockFormatter.format(block)
            } else {
                if i > 0 { result += "\n" }
                result += BlockFormatter.format(block)
            }
        }

        let titleRange = result.range(of: "# Title")!
        let insertRange = result.range(of: "Inserted.")!
        let paraRange = result.range(of: "Paragraph.")!
        XCTAssertTrue(titleRange.lowerBound < insertRange.lowerBound)
        XCTAssertTrue(insertRange.lowerBound < paraRange.lowerBound)
    }
}
