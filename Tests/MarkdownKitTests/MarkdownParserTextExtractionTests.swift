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

    func testEscapedCharactersKeepTheirBackslash() throws {
        XCTExpectFailure("""
            A backslash escape is resolved into a plain text node, and \
            getNodeText returns that node's literal, so the backslashes are lost \
            and the text reads "an escaped *asterisk*". Re-emitting that text \
            turns the two literal asterisks into emphasis, so md format silently \
            changes the meaning of the paragraph. The escapes should survive.
            """)
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

    func testEmptyListItemsAreDropped() {
        let blocks = parser.parse("-\n- second\n")
        XCTAssertEqual(blocks.count, 1)
        guard case .list(let items, _, _, _, _) = blocks[0] else {
            return XCTFail("Expected a list, got \(blocks[0])")
        }
        XCTAssertEqual(items.map(\.text), ["second"])
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

    // MARK: - Blocks the parser deliberately skips

    func testHtmlBlocksProduceNoBlockAtAll() {
        XCTAssertEqual(parser.parse("<div>\nhi\n</div>\n").count, 0)
    }

    func testAnHtmlBlockBetweenTwoParagraphsIsSilentlyDropped() {
        let blocks = parser.parse("Before.\n\n<div>x</div>\n\nAfter.\n")
        XCTAssertEqual(blocks.count, 2)
        guard case .paragraph(let first, _, _, _) = blocks[0],
              case .paragraph(let second, _, _, _) = blocks[1] else {
            return XCTFail("Expected two paragraphs, got \(blocks)")
        }
        XCTAssertEqual(first, "Before.")
        XCTAssertEqual(second, "After.")
    }

    // MARK: - Line breaks inside a block

    func testAWrappedParagraphKeepsTheBreakBetweenItsLines() throws {
        XCTExpectFailure("""
            getChildrenText walks the inline children of a paragraph and appends \
            each one's rendered text after trimming it. A soft line break renders \
            as a newline, which trimming reduces to nothing, so the two source \
            lines are welded into "line oneline two". The break should survive as \
            a newline. md format writes this back out, so any wrapped prose loses \
            a word boundary.
            """)
        XCTAssertEqual(
            try paragraphText("line one\nline two\n"),
            "line one\nline two"
        )
    }

    func testAHardLineBreakKeepsTheBreakBetweenItsLines() throws {
        XCTExpectFailure("""
            A hard line break (two trailing spaces) renders as its own inline \
            node, which getNodeText trims away entirely, so "hard break  \\nsecond" \
            becomes "hard breaksecond". The break should survive as a newline.
            """)
        XCTAssertEqual(
            try paragraphText("hard break  \nsecond\n"),
            "hard break\nsecond"
        )
    }

    func testABlockquoteKeepsTheBreakBetweenItsParagraphs() {
        XCTExpectFailure("""
            getChildrenText concatenates the rendered child blocks of a container \
            with no separator, so a blockquote holding two paragraphs collapses to \
            "AB". The paragraphs should stay separated by a blank line. md format \
            writes this back out as "> AB", running the two paragraphs together.
            """)
        let blocks = parser.parse("> A\n>\n> B\n")
        XCTAssertEqual(blocks.count, 1)
        guard case .blockquote(let text, _, _, _) = blocks[0] else {
            return XCTFail("Expected a blockquote, got \(blocks[0])")
        }
        XCTAssertEqual(text, "A\n\nB")
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
