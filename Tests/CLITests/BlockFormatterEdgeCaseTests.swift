//
//  BlockFormatterEdgeCaseTests.swift
//  md
//
//  Covers the BlockFormatter branches the parser cannot reach on its own —
//  tables, code blocks with no trailing newline, a nil language, and empty
//  collections — by building MarkdownBlock values directly.
//

import XCTest
@testable import md
@testable import MarkdownKit

final class BlockFormatterEdgeCaseTests: XCTestCase {

    let parser = MarkdownParser()

    /// Position information plays no part in formatting, so synthesized blocks
    /// carry an empty range.
    private let noRange = NSRange(location: 0, length: 0)
    private let firstLine = 1...1

    // MARK: - Tables

    func testFormatTableUnderlinesEachHeaderCell() {
        let block = MarkdownBlock.table(
            rows: [["A", "B"], ["1", "2"]],
            charRange: noRange,
            byteRange: noRange,
            lineRange: firstLine
        )
        XCTAssertEqual(
            BlockFormatter.format(block),
            "| A | B |\n| --- | --- |\n| 1 | 2 |\n"
        )
    }

    func testFormatTableWidensTheRuleToMatchLongHeaderCells() {
        let block = MarkdownBlock.table(
            rows: [["Header", "B"]],
            charRange: noRange,
            byteRange: noRange,
            lineRange: firstLine
        )
        XCTAssertEqual(
            BlockFormatter.format(block),
            "| Header | B |\n| ------ | --- |\n"
        )
    }

    func testFormatTableRuleNeverShrinksBelowThreeDashes() {
        let block = MarkdownBlock.table(
            rows: [["A"]],
            charRange: noRange,
            byteRange: noRange,
            lineRange: firstLine
        )
        XCTAssertEqual(BlockFormatter.format(block), "| A |\n| --- |\n")
    }

    func testFormatTableEmitsEveryBodyRow() {
        let block = MarkdownBlock.table(
            rows: [["A"], ["1"], ["2"], ["3"]],
            charRange: noRange,
            byteRange: noRange,
            lineRange: firstLine
        )
        XCTAssertEqual(
            BlockFormatter.format(block),
            "| A |\n| --- |\n| 1 |\n| 2 |\n| 3 |\n"
        )
    }

    func testFormatTableWithNoRowsProducesNothing() {
        let block = MarkdownBlock.table(
            rows: [],
            charRange: noRange,
            byteRange: noRange,
            lineRange: firstLine
        )
        XCTAssertEqual(BlockFormatter.format(block), "")
    }

    func testFormatTableRoundTripsAParsedTable() {
        let blocks = parser.parse("| A | B |\n| --- | --- |\n| 1 | 2 |")
        XCTAssertEqual(
            BlockFormatter.format(blocks),
            "| A | B |\n| --- | --- |\n| 1 | 2 |\n"
        )
    }

    // MARK: - Code blocks

    func testFormatCodeBlockAppendsAClosingNewlineWhenTheCodeLacksOne() {
        let block = MarkdownBlock.codeBlock(
            language: "swift",
            code: "let x = 1",
            charRange: noRange,
            byteRange: noRange,
            lineRange: firstLine
        )
        XCTAssertEqual(
            BlockFormatter.format(block),
            "```swift\nlet x = 1\n```\n"
        )
    }

    func testFormatCodeBlockDoesNotDoubleAnExistingTrailingNewline() {
        let block = MarkdownBlock.codeBlock(
            language: "swift",
            code: "let x = 1\n",
            charRange: noRange,
            byteRange: noRange,
            lineRange: firstLine
        )
        XCTAssertEqual(
            BlockFormatter.format(block),
            "```swift\nlet x = 1\n```\n"
        )
    }

    func testFormatCodeBlockWithNilLanguageEmitsABareFence() {
        let block = MarkdownBlock.codeBlock(
            language: nil,
            code: "plain\n",
            charRange: noRange,
            byteRange: noRange,
            lineRange: firstLine
        )
        XCTAssertEqual(BlockFormatter.format(block), "```\nplain\n```\n")
    }

    /// A fence must be longer than the longest run of backticks it encloses.
    /// A three backtick fence around content that itself holds a three
    /// backtick line closes at that line, which splits one code block into an
    /// empty block, a paragraph, and a second empty block.
    func testFormatCodeBlockLengthensTheFenceAroundAnEnclosedFence() {
        let block = MarkdownBlock.codeBlock(
            language: nil,
            code: "```\nstill code\n```\n",
            charRange: noRange,
            byteRange: noRange,
            lineRange: firstLine
        )
        XCTAssertEqual(
            BlockFormatter.format(block),
            "````\n```\nstill code\n```\n````\n"
        )
    }

    /// The fence grows past the longest run, not to a fixed four.
    func testFormatCodeBlockLengthensTheFencePastTheLongestRun() {
        let block = MarkdownBlock.codeBlock(
            language: nil,
            code: "`````\n",
            charRange: noRange,
            byteRange: noRange,
            lineRange: firstLine
        )
        XCTAssertEqual(
            BlockFormatter.format(block),
            "``````\n`````\n``````\n"
        )
    }

    /// A run shorter than the fence needs no growth, thus the common case
    /// keeps the three backticks it has today.
    func testFormatCodeBlockKeepsThreeBackticksAroundAShorterRun() {
        let block = MarkdownBlock.codeBlock(
            language: nil,
            code: "a ``code span`` here\n",
            charRange: noRange,
            byteRange: noRange,
            lineRange: firstLine
        )
        XCTAssertEqual(
            BlockFormatter.format(block),
            "```\na ``code span`` here\n```\n"
        )
    }

    func testFormatEmptyCodeBlockKeepsTheFencesOnSeparateLines() {
        let block = MarkdownBlock.codeBlock(
            language: "",
            code: "",
            charRange: noRange,
            byteRange: noRange,
            lineRange: firstLine
        )
        XCTAssertEqual(BlockFormatter.format(block), "```\n\n```\n")
    }

    // MARK: - Lists

    func testFormatNestedListIndentsEachLevelByFourSpaces() {
        let blocks = parser.parse("- Parent\n    - Child\n        - Grandchild")
        XCTAssertEqual(
            BlockFormatter.format(blocks),
            "- Parent\n    - Child\n        - Grandchild\n"
        )
    }

    /// The marker comes from the item, not the enclosing list, so an ordered
    /// list nested inside an unordered one keeps its own numbering marker.
    func testFormatMarkerFollowsTheItemRatherThanTheList() {
        let block = MarkdownBlock.list(
            items: [
                ListItem(text: "bullet", indentLevel: 0, ordered: false),
                ListItem(text: "number", indentLevel: 1, ordered: true)
            ],
            ordered: false,
            charRange: noRange,
            byteRange: noRange,
            lineRange: firstLine
        )
        XCTAssertEqual(
            BlockFormatter.format(block),
            "- bullet\n    1. number\n"
        )
    }

    func testFormatListWithNoItemsProducesNothing() {
        let block = MarkdownBlock.list(
            items: [],
            ordered: true,
            charRange: noRange,
            byteRange: noRange,
            lineRange: firstLine
        )
        XCTAssertEqual(BlockFormatter.format(block), "")
    }

    func testFormatOrderedListRenumbersEveryItemAsOne() {
        let blocks = parser.parse("3. three\n4. four\n5. five")
        XCTAssertEqual(
            BlockFormatter.format(blocks),
            "1. three\n1. four\n1. five\n"
        )
    }

    // MARK: - Blockquotes

    func testFormatBlockquotePrefixesEveryLine() {
        let block = MarkdownBlock.blockquote(
            text: "first\nsecond",
            charRange: noRange,
            byteRange: noRange,
            lineRange: firstLine
        )
        XCTAssertEqual(
            BlockFormatter.format(block),
            "> first\n> second\n"
        )
    }

    func testFormatBlockquoteKeepsInteriorBlankLines() {
        let block = MarkdownBlock.blockquote(
            text: "first\n\nsecond",
            charRange: noRange,
            byteRange: noRange,
            lineRange: firstLine
        )
        XCTAssertEqual(
            BlockFormatter.format(block),
            "> first\n> \n> second\n"
        )
    }

    func testFormatBlockquoteCarriesSoftLineBreaksThrough() {
        let blocks = parser.parse("> line one\n> line two")
        XCTAssertEqual(
            BlockFormatter.format(blocks),
            "> line one\n> line two\n"
        )
    }

    // MARK: - Headings

    func testFormatHeadingUsesOneHashPerLevel() {
        for level in 1...6 {
            let block = MarkdownBlock.heading(
                level: level,
                text: "Title",
                charRange: noRange,
                byteRange: noRange,
                lineRange: firstLine
            )
            XCTAssertEqual(
                BlockFormatter.format(block),
                "\(String(repeating: "#", count: level)) Title\n",
                "level \(level) should emit \(level) hashes"
            )
        }
    }

    // MARK: - Block joining

    func testFormatSeparatesConsecutiveBlocksWithOneBlankLine() {
        let blocks = parser.parse("# A\n\n# B\n\n# C")
        XCTAssertEqual(BlockFormatter.format(blocks), "# A\n\n# B\n\n# C\n")
    }

    func testFormatDoesNotPrefixTheFirstBlockWithABlankLine() {
        let blocks = parser.parse("# A")
        XCTAssertEqual(BlockFormatter.format(blocks), "# A\n")
    }

    /// A block that formats to nothing still contributes its separator, so an
    /// empty table between two headings leaves a run of blank lines behind.
    func testEmptyBlockStillContributesItsSeparator() {
        let blocks: [MarkdownBlock] = [
            .heading(level: 1, text: "A", charRange: noRange, byteRange: noRange, lineRange: firstLine),
            .table(rows: [], charRange: noRange, byteRange: noRange, lineRange: firstLine),
            .heading(level: 1, text: "B", charRange: noRange, byteRange: noRange, lineRange: firstLine)
        ]
        XCTAssertEqual(BlockFormatter.format(blocks), "# A\n\n\n# B\n")
    }
}
