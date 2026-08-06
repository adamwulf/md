//
//  MarkdownBlockRangeTests.swift
//  md
//
//  Covers the three position accessors on MarkdownBlock for every case, and
//  the line table that converts cmark's line/column pairs into byte and UTF-16
//  offsets — including documents that mix line endings or multi-byte text.
//

import XCTest
@testable import MarkdownKit

final class MarkdownBlockRangeTests: XCTestCase {

    let parser = MarkdownParser()

    private let charRange = NSRange(location: 10, length: 5)
    private let byteRange = NSRange(location: 20, length: 7)
    private let lineRange = 3...4

    /// One value of every case, all carrying the same distinct ranges.
    private var everyCase: [MarkdownBlock] {
        [
            .heading(level: 1, text: "h", charRange: charRange, byteRange: byteRange, lineRange: lineRange),
            .paragraph(text: "p", charRange: charRange, byteRange: byteRange, lineRange: lineRange),
            .codeBlock(language: "swift", code: "c", charRange: charRange, byteRange: byteRange, lineRange: lineRange),
            .list(items: [], ordered: false, charRange: charRange, byteRange: byteRange, lineRange: lineRange),
            .blockquote(text: "q", charRange: charRange, byteRange: byteRange, lineRange: lineRange),
            .thematicBreak(charRange: charRange, byteRange: byteRange, lineRange: lineRange),
            .table(rows: [], charRange: charRange, byteRange: byteRange, lineRange: lineRange),
            .htmlBlock(literal: "<div></div>", charRange: charRange, byteRange: byteRange, lineRange: lineRange)
        ]
    }

    // MARK: - Accessors

    func testCharRangeIsReadableFromEveryCase() {
        for block in everyCase {
            XCTAssertEqual(block.charRange, charRange, "for \(block)")
        }
    }

    func testByteRangeIsReadableFromEveryCase() {
        for block in everyCase {
            XCTAssertEqual(block.byteRange, byteRange, "for \(block)")
        }
    }

    func testLineRangeIsReadableFromEveryCase() {
        for block in everyCase {
            XCTAssertEqual(block.lineRange, lineRange, "for \(block)")
        }
    }

    func testEveryCaseIsRepresentedExactlyOnce() {
        XCTAssertEqual(everyCase.count, 8)
    }

    // MARK: - ListItem

    func testListItemsAreEqualOnlyWhenAllThreeFieldsMatch() {
        let base = ListItem(text: "a", indentLevel: 0, ordered: false)
        XCTAssertEqual(base, ListItem(text: "a", indentLevel: 0, ordered: false))
        XCTAssertNotEqual(base, ListItem(text: "b", indentLevel: 0, ordered: false))
        XCTAssertNotEqual(base, ListItem(text: "a", indentLevel: 1, ordered: false))
        XCTAssertNotEqual(base, ListItem(text: "a", indentLevel: 0, ordered: true))
    }

    // MARK: - Byte ranges address the source exactly

    /// Slices `markdown` with each block's byte range and compares against the
    /// source text those blocks should cover.
    private func assertByteRanges(
        _ markdown: String,
        cover expected: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let blocks = parser.parse(markdown)
        let utf8 = Array(markdown.utf8)
        XCTAssertEqual(blocks.count, expected.count, "block count", file: file, line: line)
        for (block, source) in zip(blocks, expected) {
            let range = block.byteRange
            let slice = utf8[range.location..<(range.location + range.length)]
            XCTAssertEqual(
                String(decoding: slice, as: UTF8.self),
                source,
                file: file,
                line: line
            )
        }
    }

    private func assertCharRanges(
        _ markdown: String,
        cover expected: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let blocks = parser.parse(markdown)
        let nsString = markdown as NSString
        XCTAssertEqual(blocks.count, expected.count, "block count", file: file, line: line)
        for (block, source) in zip(blocks, expected) {
            XCTAssertEqual(
                nsString.substring(with: block.charRange),
                source,
                file: file,
                line: line
            )
        }
    }

    func testByteRangesAddressLineFeedSource() {
        assertByteRanges("# One\n\n# Two\n", cover: ["# One", "# Two"])
    }

    func testListRangesStopBeforeTheBlankLineBelowThem() {
        let markdown = "- a\n- b\n\nAfter.\n"
        let blocks = parser.parse(markdown)
        XCTAssertEqual(blocks.first?.lineRange, 1...2)
        assertByteRanges(markdown, cover: ["- a\n- b", "After."])
        assertCharRanges(markdown, cover: ["- a\n- b", "After."])
    }

    func testListRangesDropEveryTrailingBlankLine() {
        let blocks = parser.parse("- a\n- b\n\n\nAfter.\n")
        XCTAssertEqual(blocks.first?.lineRange, 1...2)
    }

    func testListRangesStopBeforeACarriageReturnLineFeedBlankLine() {
        let markdown = "- a\r\n- b\r\n\r\nAfter.\r\n"
        let blocks = parser.parse(markdown)
        XCTAssertEqual(blocks.first?.lineRange, 1...2)
        assertByteRanges(markdown, cover: ["- a\r\n- b", "After."])
        assertCharRanges(markdown, cover: ["- a\r\n- b", "After."])
    }

    func testListRangesTreatWhitespaceOnlyLinesAsBlank() {
        let blocks = parser.parse("- a\n- b\n \t \nAfter.\n")
        XCTAssertEqual(blocks.first?.lineRange, 1...2)
    }

    func testListRangesKeepNonBreakingSpaceContent() {
        let markdown = "- a\n\u{00A0}\n\nAfter.\n"
        let blocks = parser.parse(markdown)
        XCTAssertEqual(blocks.first?.lineRange, 1...2)
        assertByteRanges(markdown, cover: ["- a\n\u{00A0}", "After."])
        assertCharRanges(markdown, cover: ["- a\n\u{00A0}", "After."])
    }

    func testListRangesKeepEmSpaceContentWithCarriageReturnLineFeeds() {
        let markdown = "- a\r\n\u{2003}\r\n\r\nAfter.\r\n"
        let blocks = parser.parse(markdown)
        XCTAssertEqual(blocks.first?.lineRange, 1...2)
        assertByteRanges(markdown, cover: ["- a\r\n\u{2003}", "After."])
        assertCharRanges(markdown, cover: ["- a\r\n\u{2003}", "After."])
    }

    func testListRangesAddressMultibyteFinalItemsWithCarriageReturnLineFeeds() {
        let markdown = "- alpha\r\n- 🌍\r\n\r\nAfter.\r\n"
        let blocks = parser.parse(markdown)
        XCTAssertEqual(blocks.first?.lineRange, 1...2)
        assertByteRanges(markdown, cover: ["- alpha\r\n- 🌍", "After."])
        assertCharRanges(markdown, cover: ["- alpha\r\n- 🌍", "After."])
    }

    func testByteRangesAddressLoneCarriageReturnSource() {
        assertByteRanges("# One\r\r# Two\r", cover: ["# One", "# Two"])
    }

    func testByteRangesAddressSourceWithoutATrailingNewline() {
        assertByteRanges("# One\n\n# Two", cover: ["# One", "# Two"])
    }

    func testByteRangesAddressMultiByteSource() {
        assertByteRanges(
            "# Héllo 🌍\n\nCafé déjà vu\n",
            cover: ["# Héllo 🌍", "Café déjà vu"]
        )
    }

    func testCharRangesAddressMultiByteSource() {
        assertCharRanges(
            "# Héllo 🌍\n\nCafé déjà vu\n",
            cover: ["# Héllo 🌍", "Café déjà vu"]
        )
    }

    /// A multi-byte character earlier in the document shifts the byte offsets
    /// past it but not the UTF-16 offsets, so the two ranges must diverge.
    /// "# 🌍" is 6 UTF-8 bytes but only 4 UTF-16 units, and two newlines follow.
    func testByteAndCharacterOffsetsDivergeAfterMultiByteText() {
        let markdown = "# 🌍\n\n# After\n"
        let blocks = parser.parse(markdown)
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[1].byteRange, NSRange(location: 8, length: 7))
        XCTAssertEqual(blocks[1].charRange, NSRange(location: 6, length: 7))
    }

    func testCharRangesAddressCarriageReturnLineFeedSource() {
        assertCharRanges("# One\r\n\r\n# Two\r\n", cover: ["# One", "# Two"])
    }

    func testMultilineDelimiterTerminatedHtmlRangesCoverTheirClosingLines() {
        let htmlBlocks = [
            "<script>\nconst café = 1\n</script>",
            "<!--\ncomment 🌍\n-->",
            "<?target\nvalue 🌍\n?>",
            "<!DOCTYPE\nhtml 🌍>",
            "<![CDATA[\n<raw 🌍>\n]]>"
        ]

        for html in htmlBlocks {
            let crlfHTML = html.replacingOccurrences(of: "\n", with: "\r\n")
            let markdown = "Before 🌍.\r\n\r\n\(crlfHTML)\r\n\r\nAfter.\r\n"
            let blocks = parser.parse(markdown)
            let htmlLineCount = html.split(separator: "\n").count

            XCTAssertEqual(blocks.count, 3, "for \(html)")
            XCTAssertEqual(blocks[1].lineRange, 3...(2 + htmlLineCount), "for \(html)")
            assertByteRanges(
                markdown,
                cover: ["Before 🌍.", crlfHTML, "After."]
            )
            assertCharRanges(
                markdown,
                cover: ["Before 🌍.", crlfHTML, "After."]
            )
        }
    }

    // MARK: - Line ranges

    func testLineRangesCountCarriageReturnLineFeedPairsAsOneLine() {
        let blocks = parser.parse("# One\r\n\r\n# Two\r\n")
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0].lineRange, 1...1)
        XCTAssertEqual(blocks[1].lineRange, 3...3)
    }

    func testLineRangesCountLoneCarriageReturnsAsOneLine() {
        let blocks = parser.parse("# One\r\r# Two\r")
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0].lineRange, 1...1)
        XCTAssertEqual(blocks[1].lineRange, 3...3)
    }

    func testLineRangeOfAMultiLineBlockSpansItsWholeSource() {
        let blocks = parser.parse("```\na\nb\nc\n```\n")
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].lineRange, 1...5)
    }

    func testLineRangeOfATableSpansHeaderRuleAndBody() {
        let blocks = parser.parse("| A |\n| --- |\n| 1 |\n| 2 |\n")
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].lineRange, 1...4)
    }

    func testBlankLinesBetweenBlocksAreCounted() {
        let blocks = parser.parse("# One\n\n\n\n# Two\n")
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[1].lineRange, 5...5)
    }

    // MARK: - Documents the parser must not choke on

    func testAMixtureOfLineEndingsInOneDocumentIsParsed() {
        let blocks = parser.parse("# One\r\n\n# Two\r\r# Three\n")
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[0].lineRange, 1...1)
        XCTAssertEqual(blocks[1].lineRange, 3...3)
        XCTAssertEqual(blocks[2].lineRange, 5...5)
    }

    func testADocumentOfNothingButNewlinesHasNoBlocks() {
        XCTAssertEqual(parser.parse("\n\n\n").count, 0)
    }

    func testADocumentOfNothingButCarriageReturnsHasNoBlocks() {
        XCTAssertEqual(parser.parse("\r\r\r").count, 0)
    }

    func testASingleCharacterDocumentIsOneParagraph() {
        let blocks = parser.parse("x")
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].byteRange, NSRange(location: 0, length: 1))
        XCTAssertEqual(blocks[0].lineRange, 1...1)
    }

    func testALongDocumentKeepsEveryBlockInSourceOrder() {
        let markdown = (1...50)
            .map { "# Heading \($0)" }
            .joined(separator: "\n\n")
        let blocks = parser.parse(markdown)
        XCTAssertEqual(blocks.count, 50)
        let utf8 = Array(markdown.utf8)
        for (index, block) in blocks.enumerated() {
            let range = block.byteRange
            let slice = utf8[range.location..<(range.location + range.length)]
            XCTAssertEqual(
                String(decoding: slice, as: UTF8.self),
                "# Heading \(index + 1)"
            )
            XCTAssertEqual(block.lineRange, (index * 2 + 1)...(index * 2 + 1))
        }
    }
}
