//
//  MarkdownParserTextExtractionTests.swift
//  md
//
//  Pins down the text MarkdownParser lifts out of each block: which inline
//  markup survives, and what happens to the breaks between lines and between
//  the child blocks of a container.
//

import XCTest
@testable import MarkdownKit

final class MarkdownParserTextExtractionTests: XCTestCase {

    let parser = MarkdownParser()

    private func paragraphText(
        _ markdown: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        let blocks = parser.parse(markdown)
        let first = try XCTUnwrap(blocks.first, file: file, line: line)
        guard case .paragraph(let text, _, _, _) = first else {
            XCTFail("Expected a paragraph, got \(first)", file: file, line: line)
            return ""
        }
        return text
    }

    // MARK: - Inline markup is preserved verbatim

    func testEmphasisMarkersSurviveInParagraphText() throws {
        XCTAssertEqual(
            try paragraphText("a **bold** and *italic* c"),
            "a **bold** and *italic* c"
        )
    }

    func testInlineCodeBackticksSurviveInParagraphText() throws {
        XCTAssertEqual(
            try paragraphText("text with `code` inline"),
            "text with `code` inline"
        )
    }

    func testLinkSyntaxSurvivesInParagraphText() throws {
        XCTAssertEqual(
            try paragraphText("a [link](http://example.com) b"),
            "a [link](http://example.com) b"
        )
    }

    func testStrikethroughSurvivesInParagraphText() throws {
        XCTAssertEqual(
            try paragraphText("a ~~struck~~ b"),
            "a ~~struck~~ b"
        )
    }

    /// Fixed by `MarkdownEscaper`: the parser gives block text as markdown source, thus
    /// a backslash that the source needs comes back. See `MarkdownEscapeTests`.
    func testEscapedCharactersKeepTheirBackslash() throws {
        XCTAssertEqual(
            try paragraphText("an escaped \\*asterisk\\*"),
            "an escaped \\*asterisk\\*"
        )
    }

    func testLeadingAndTrailingWhitespaceIsTrimmed() throws {
        XCTAssertEqual(try paragraphText("   padded   "), "padded")
    }

    // MARK: - Heading text

    func testHeadingTextExcludesTheHashMarkers() {
        let blocks = parser.parse("###   Spaced Out   ")
        XCTAssertEqual(blocks.count, 1)
        guard case .heading(let level, let text, _, _, _) = blocks[0] else {
            return XCTFail("Expected a heading, got \(blocks[0])")
        }
        XCTAssertEqual(level, 3)
        XCTAssertEqual(text, "Spaced Out")
    }

    func testSetextHeadingIsReportedAsLevelOne() {
        let blocks = parser.parse("Title\n=====\n")
        XCTAssertEqual(blocks.count, 1)
        guard case .heading(let level, let text, _, _, _) = blocks[0] else {
            return XCTFail("Expected a heading, got \(blocks[0])")
        }
        XCTAssertEqual(level, 1)
        XCTAssertEqual(text, "Title")
    }

    func testSetextHeadingWithDashesIsReportedAsLevelTwo() {
        let blocks = parser.parse("Title\n-----\n")
        XCTAssertEqual(blocks.count, 1)
        guard case .heading(let level, _, _, _, _) = blocks[0] else {
            return XCTFail("Expected a heading, got \(blocks[0])")
        }
        XCTAssertEqual(level, 2)
    }

    // MARK: - Code block text

    func testCodeBlockKeepsItsIndentationAndTrailingNewline() {
        let blocks = parser.parse("```swift\n    indented\n\nblank above\n```")
        XCTAssertEqual(blocks.count, 1)
        guard case .codeBlock(let language, let code, _, _, _) = blocks[0] else {
            return XCTFail("Expected a code block, got \(blocks[0])")
        }
        XCTAssertEqual(language, "swift")
        XCTAssertEqual(code, "    indented\n\nblank above\n")
    }

    func testIndentedCodeBlockReportsAnEmptyLanguage() {
        let blocks = parser.parse("    four space indent\n")
        XCTAssertEqual(blocks.count, 1)
        guard case .codeBlock(let language, let code, _, _, _) = blocks[0] else {
            return XCTFail("Expected a code block, got \(blocks[0])")
        }
        XCTAssertEqual(language, "")
        XCTAssertEqual(code, "four space indent\n")
    }

    func testFenceInfoBeyondTheLanguageIsKept() {
        let blocks = parser.parse("```swift showLineNumbers\nx\n```")
        XCTAssertEqual(blocks.count, 1)
        guard case .codeBlock(let language, _, _, _, _) = blocks[0] else {
            return XCTFail("Expected a code block, got \(blocks[0])")
        }
        XCTAssertEqual(language, "swift showLineNumbers")
    }

    // MARK: - Table cell text

    func testTableCellsAreTrimmed() {
        let blocks = parser.parse("|  A  |   B |\n| --- | --- |\n| 1 |  2  |\n")
        XCTAssertEqual(blocks.count, 1)
        guard case .table(let rows, _, _, _) = blocks[0] else {
            return XCTFail("Expected a table, got \(blocks[0])")
        }
        XCTAssertEqual(rows, [["A", "B"], ["1", "2"]])
    }

    func testTableKeepsInlineMarkupInsideCells() {
        let blocks = parser.parse("| **A** |\n| --- |\n| `b` |\n")
        XCTAssertEqual(blocks.count, 1)
        guard case .table(let rows, _, _, _) = blocks[0] else {
            return XCTFail("Expected a table, got \(blocks[0])")
        }
        XCTAssertEqual(rows, [["**A**"], ["`b`"]])
    }

    func testTableWithNoBodyRowsReportsOnlyItsHeader() {
        let blocks = parser.parse("| A | B |\n| --- | --- |\n")
        XCTAssertEqual(blocks.count, 1)
        guard case .table(let rows, _, _, _) = blocks[0] else {
            return XCTFail("Expected a table, got \(blocks[0])")
        }
        XCTAssertEqual(rows, [["A", "B"]])
    }

    /// cmark-gfm pads a short body row out to the header's column count, so
    /// every row a table reports has the same width.
    func testTableBodyRowShorterThanTheHeaderIsPaddedWithAnEmptyCell() {
        let blocks = parser.parse("| A | B |\n| --- | --- |\n| 1 |\n")
        XCTAssertEqual(blocks.count, 1)
        guard case .table(let rows, _, _, _) = blocks[0] else {
            return XCTFail("Expected a table, got \(blocks[0])")
        }
        XCTAssertEqual(rows, [["A", "B"], ["1", ""]])
    }

    // MARK: - List item text

    func testListItemTextExcludesTheMarker() {
        let blocks = parser.parse("- first\n- second\n")
        XCTAssertEqual(blocks.count, 1)
        guard case .list(let items, _, _, _, _) = blocks[0] else {
            return XCTFail("Expected a list, got \(blocks[0])")
        }
        XCTAssertEqual(items.map(\.text), ["first", "second"])
    }

    /// This test used to be `testEmptyListItemsAreDropped` and asserted
    /// `["second"]`. Dropping the item was a defect, not a decision: the
    /// author wrote two bullets, `format` writes the file, and one run left
    /// one bullet behind with nothing to say the other had ever been there.
    /// The expectation is corrected rather than deleted so the old behaviour
    /// cannot quietly come back.
    func testAnEmptyListItemIsKept() {
        let blocks = parser.parse("-\n- second\n")
        XCTAssertEqual(blocks.count, 1)
        guard case .list(let items, _, _, _, _) = blocks[0] else {
            return XCTFail("Expected a list, got \(blocks[0])")
        }
        XCTAssertEqual(items.map(\.text), ["", "second"])
    }

    func testAParentItemIsEmittedBeforeItsNestedChildren() {
        let blocks = parser.parse("- parent\n    - child\n- sibling\n")
        XCTAssertEqual(blocks.count, 1)
        guard case .list(let items, _, _, _, _) = blocks[0] else {
            return XCTFail("Expected a list, got \(blocks[0])")
        }
        XCTAssertEqual(
            items,
            [
                ListItem(text: "parent", indentLevel: 0, ordered: false),
                ListItem(text: "child", indentLevel: 1, ordered: false),
                ListItem(text: "sibling", indentLevel: 0, ordered: false)
            ]
        )
    }

    func testANestedOrderedListInsideAnUnorderedListKeepsItsOwnKind() {
        let blocks = parser.parse("- parent\n    1. numbered\n")
        XCTAssertEqual(blocks.count, 1)
        guard case .list(let items, let ordered, _, _, _) = blocks[0] else {
            return XCTFail("Expected a list, got \(blocks[0])")
        }
        XCTAssertFalse(ordered)
        XCTAssertEqual(
            items,
            [
                ListItem(text: "parent", indentLevel: 0, ordered: false),
                ListItem(text: "numbered", indentLevel: 1, ordered: true)
            ]
        )
    }

    func testAnItemHoldingOnlyANestedListDoesNotEmitAnEmptyParent() {
        let blocks = parser.parse("-   - only child\n")
        XCTAssertEqual(blocks.count, 1)
        guard case .list(let items, _, _, _, _) = blocks[0] else {
            return XCTFail("Expected a list, got \(blocks[0])")
        }
        XCTAssertEqual(
            items,
            [ListItem(text: "only child", indentLevel: 1, ordered: false)]
        )
    }

    // MARK: - Raw HTML blocks

    func testHtmlBlocksKeepTheirLiteralText() {
        let blocks = parser.parse("<div>\nhi\n</div>\n")
        XCTAssertEqual(blocks.count, 1)
        guard case .htmlBlock(let literal, _, _, _) = blocks[0] else {
            return XCTFail("Expected an HTML block, got \(blocks[0])")
        }
        XCTAssertEqual(literal, "<div>\nhi\n</div>\n")
    }

    func testAnHtmlBlockBetweenTwoParagraphsIsKeptInSourceOrder() {
        let blocks = parser.parse("Before.\n\n<div>x</div>\n\nAfter.\n")
        XCTAssertEqual(blocks.count, 3)
        guard case .paragraph(let first, _, _, _) = blocks[0],
              case .htmlBlock(let literal, _, _, _) = blocks[1],
              case .paragraph(let second, _, _, _) = blocks[2] else {
            return XCTFail("Expected paragraph, HTML, paragraph; got \(blocks)")
        }
        XCTAssertEqual(first, "Before.")
        XCTAssertEqual(literal, "<div>x</div>\n")
        XCTAssertEqual(second, "After.")
    }

    // MARK: - Line breaks inside a block

    func testAWrappedParagraphKeepsTheBreakBetweenItsLines() throws {
        XCTAssertEqual(
            try paragraphText("line one\nline two\n"),
            "line one\nline two"
        )
    }

    /// The block text is markdown source, thus the break keeps the spelling that says
    /// it is HARD. A bare newline is the spelling of a SOFT break, which a reader shows
    /// as a space, thus it would say something the source does not say.
    ///
    /// Of the two spellings the parser writes the backslash, because two spaces at the
    /// end of a line are invisible and easy for another tool to take off.
    func testAHardLineBreakKeepsTheBreakBetweenItsLines() throws {
        XCTAssertEqual(
            try paragraphText("hard break  \nsecond\n"),
            "hard break\\\nsecond"
        )
    }

    /// The backslash spelling of the same break gives the same block text.
    func testTheBackslashSpellingOfAHardBreakGivesTheSameText() throws {
        XCTAssertEqual(
            try paragraphText("hard break\\\nsecond\n"),
            "hard break\\\nsecond"
        )
    }

    /// A hard break stays hard through a round trip: what the parser writes back reads
    /// as a hard break again, and not as a soft one.
    func testAHardLineBreakSurvivesASecondParse() throws {
        let once = try paragraphText("hard break  \nsecond\n")
        XCTAssertEqual(try paragraphText(once + "\n"), once)
    }

    func testABlockquoteKeepsTheBreakBetweenItsParagraphs() {
        let blocks = parser.parse("> A\n>\n> B\n")
        XCTAssertEqual(blocks.count, 1)
        guard case .blockquote(let text, _, _, _) = blocks[0] else {
            return XCTFail("Expected a blockquote, got \(blocks[0])")
        }
        XCTAssertEqual(text, "A\n\nB")
    }

    func testABlockquoteKeepsAHeadingApartFromTheParagraphBelowIt() {
        let blocks = parser.parse("> # Heading\n>\n> Paragraph.\n")
        XCTAssertEqual(blocks.count, 1)
        guard case .blockquote(let text, _, _, _) = blocks[0] else {
            return XCTFail("Expected a blockquote, got \(blocks[0])")
        }
        XCTAssertEqual(text, "# Heading\n\nParagraph.")
    }

    func testABlockquoteKeepsSoftBreaksWithinOneParagraph() {
        let blocks = parser.parse("> line one\n> line two\n")
        XCTAssertEqual(blocks.count, 1)
        guard case .blockquote(let text, _, _, _) = blocks[0] else {
            return XCTFail("Expected a blockquote, got \(blocks[0])")
        }
        XCTAssertEqual(text, "line one\nline two")
    }

    func testANestedBlockquoteIsRenderedIntoItsParentText() {
        let blocks = parser.parse("> > inner\n")
        XCTAssertEqual(blocks.count, 1)
        guard case .blockquote(let text, _, _, _) = blocks[0] else {
            return XCTFail("Expected a blockquote, got \(blocks[0])")
        }
        XCTAssertEqual(text, "> inner")
    }
}
