//
//  MarkdownSourceEditorTests.swift
//  md
//
//  Direct tests for MarkdownSourceEditor.inserting: which line ending the
//  insertion adopts, how the insertion is normalized, and when the editor
//  refuses to locate the target line at all.
//

import XCTest
@testable import md
@testable import MarkdownKit

final class MarkdownSourceEditorTests: XCTestCase {

    let parser = MarkdownParser()

    private let noRange = NSRange(location: 0, length: 0)

    /// A block that carries nothing but the line it claims to start on.
    private func block(startingOnLine line: Int) -> MarkdownBlock {
        .paragraph(
            text: "",
            charRange: noRange,
            byteRange: noRange,
            lineRange: line...line
        )
    }

    // MARK: - Locating the target line

    func testInsertingReturnsNilWhenTheLineNumberIsBelowOne() {
        XCTAssertNil(
            MarkdownSourceEditor.inserting(
                "New.\n",
                before: block(startingOnLine: 0),
                in: "# One\n\n# Two\n"
            )
        )
    }

    func testInsertingReturnsNilForANegativeLineNumber() {
        XCTAssertNil(
            MarkdownSourceEditor.inserting(
                "New.\n",
                before: block(startingOnLine: -3),
                in: "# One\n\n# Two\n"
            )
        )
    }

    func testInsertingReturnsNilWhenTheLineNumberIsPastTheLastLine() {
        XCTAssertNil(
            MarkdownSourceEditor.inserting(
                "New.\n",
                before: block(startingOnLine: 99),
                in: "# One\n\n# Two\n"
            )
        )
    }

    func testInsertingReturnsNilForAnyLineBeyondTheFirstOfAnUnterminatedSource() {
        XCTAssertNil(
            MarkdownSourceEditor.inserting(
                "New.\n",
                before: block(startingOnLine: 2),
                in: "# Only"
            )
        )
    }

    func testInsertingAtLineOneAlwaysSucceedsEvenForAnEmptySource() {
        XCTAssertEqual(
            MarkdownSourceEditor.inserting(
                "New.\n",
                before: block(startingOnLine: 1),
                in: ""
            ),
            "New.\n"
        )
    }

    func testInsertingLandsAtTheStartOfTheTargetLine() {
        XCTAssertEqual(
            MarkdownSourceEditor.inserting(
                "New.\n",
                before: block(startingOnLine: 3),
                in: "one\ntwo\nthree\n"
            ),
            "one\ntwo\nNew.\nthree\n"
        )
    }

    func testInsertingAtTheLineAfterTheLastLineEndingSucceeds() {
        XCTAssertEqual(
            MarkdownSourceEditor.inserting(
                "New.\n",
                before: block(startingOnLine: 2),
                in: "one\n"
            ),
            "one\nNew.\n"
        )
    }

    // MARK: - Line ending taken from the preceding line

    func testInsertionAdoptsTheLineEndingDirectlyBeforeTheTargetLine() {
        XCTAssertEqual(
            MarkdownSourceEditor.inserting(
                "a\nb\n",
                before: block(startingOnLine: 2),
                in: "one\r\ntwo\n"
            ),
            "one\r\na\r\nb\r\ntwo\n"
        )
    }

    func testInsertionPrefersThePrecedingLineEndingOverTheDocumentFirst() {
        XCTAssertEqual(
            MarkdownSourceEditor.inserting(
                "a\n",
                before: block(startingOnLine: 3),
                in: "one\r\ntwo\nthree"
            ),
            "one\r\ntwo\na\nthree"
        )
    }

    // MARK: - Line ending taken from the first ending in the document

    func testInsertingAtLineOneAdoptsTheFirstLineFeedInTheDocument() {
        XCTAssertEqual(
            MarkdownSourceEditor.inserting(
                "a\n",
                before: block(startingOnLine: 1),
                in: "one\ntwo\n"
            ),
            "a\none\ntwo\n"
        )
    }

    func testInsertingAtLineOneAdoptsAFirstCarriageReturnLineFeedPair() {
        XCTAssertEqual(
            MarkdownSourceEditor.inserting(
                "a\n",
                before: block(startingOnLine: 1),
                in: "one\r\ntwo\r\n"
            ),
            "a\r\none\r\ntwo\r\n"
        )
    }

    func testInsertingAtLineOneAdoptsALoneCarriageReturn() {
        XCTAssertEqual(
            MarkdownSourceEditor.inserting(
                "a\n",
                before: block(startingOnLine: 1),
                in: "one\rtwo\r"
            ),
            "a\rone\rtwo\r"
        )
    }

    /// A carriage return as the very last byte has no following byte to inspect,
    /// so it is still recognized as a lone-CR ending.
    func testInsertingAtLineOneAdoptsATrailingCarriageReturn() {
        XCTAssertEqual(
            MarkdownSourceEditor.inserting(
                "a\n",
                before: block(startingOnLine: 1),
                in: "one\r"
            ),
            "a\rone\r"
        )
    }

    func testInsertingFallsBackToLineFeedWhenTheSourceHasNoLineEnding() {
        XCTAssertEqual(
            MarkdownSourceEditor.inserting(
                "a\nb\n",
                before: block(startingOnLine: 1),
                in: "# Only"
            ),
            "a\nb\n# Only"
        )
    }

    /// A multi-byte character before the first line ending must not be mistaken
    /// for one while scanning UTF-8.
    func testFirstLineEndingScanSkipsMultiByteCharacters() {
        XCTAssertEqual(
            MarkdownSourceEditor.inserting(
                "a\n",
                before: block(startingOnLine: 1),
                in: "héllo 🌍\r\nnext\r\n"
            ),
            "a\r\nhéllo 🌍\r\nnext\r\n"
        )
    }

    // MARK: - Normalizing the inserted text

    func testInsertionCarriageReturnLineFeedPairsAreRewrittenToTheTargetEnding() {
        XCTAssertEqual(
            MarkdownSourceEditor.inserting(
                "a\r\nb\r\n",
                before: block(startingOnLine: 1),
                in: "one\ntwo\n"
            ),
            "a\nb\none\ntwo\n"
        )
    }

    func testInsertionLoneCarriageReturnsAreRewrittenToTheTargetEnding() {
        XCTAssertEqual(
            MarkdownSourceEditor.inserting(
                "a\rb\r",
                before: block(startingOnLine: 1),
                in: "one\ntwo\n"
            ),
            "a\nb\none\ntwo\n"
        )
    }

    func testInsertionMixedLineEndingsAllBecomeTheTargetEnding() {
        XCTAssertEqual(
            MarkdownSourceEditor.inserting(
                "a\r\nb\rc\n",
                before: block(startingOnLine: 1),
                in: "one\r\n"
            ),
            "a\r\nb\r\nc\r\none\r\n"
        )
    }

    func testInsertionWithoutLineEndingsIsCopiedVerbatim() {
        XCTAssertEqual(
            MarkdownSourceEditor.inserting(
                "prefix ",
                before: block(startingOnLine: 1),
                in: "one\ntwo\n"
            ),
            "prefix one\ntwo\n"
        )
    }

    func testEmptyInsertionLeavesTheSourceUnchanged() {
        XCTAssertEqual(
            MarkdownSourceEditor.inserting(
                "",
                before: block(startingOnLine: 2),
                in: "one\ntwo\n"
            ),
            "one\ntwo\n"
        )
    }

    // MARK: - Real parsed blocks

    func testInsertingBeforeAParsedBlockKeepsEveryOtherByte() throws {
        let source = "# Title\n\nBody with  odd   spacing.\n\n## Target\n\nTail.\n"
        let target = try XCTUnwrap(
            parser.parse(source).first { block in
                guard case .heading(_, let text, _, _, _) = block else { return false }
                return text == "Target"
            }
        )
        XCTAssertEqual(
            MarkdownSourceEditor.inserting("New.\n\n", before: target, in: source),
            "# Title\n\nBody with  odd   spacing.\n\n"
                + "New.\n\n## Target\n\nTail.\n"
        )
    }

    /// Three spaces still leave a heading (four would make it a code block).
    /// The insertion goes to column zero so the indentation stays with the
    /// heading rather than becoming part of the inserted text.
    func testInsertingBeforeAnIndentedBlockStartsAtColumnZero() throws {
        let source = "   # Indented\n\nBody.\n"
        let target = try XCTUnwrap(parser.parse(source).first)
        guard case .heading = target else {
            return XCTFail("Expected the indented line to parse as a heading, got \(target)")
        }
        XCTAssertEqual(
            MarkdownSourceEditor.inserting("New.\n\n", before: target, in: source),
            "New.\n\n   # Indented\n\nBody.\n"
        )
    }

    // MARK: - Replacing parsed blocks

    func testReplacingAMiddleBlockKeepsUntouchedSourceBytes() {
        let source = "#    Loose heading\n\nDelete me.\n\n***\n"
        let blocks = parser.parseDocument(source)

        XCTAssertEqual(
            MarkdownSourceEditor.replacing(
                blocks: 1...1,
                in: blocks,
                with: "Replacement.\n",
                within: source
            ),
            "#    Loose heading\n\nReplacement.\n\n***\n"
        )
    }

    func testRemovingAMiddleBlockCollapsesWideSeparators() {
        let source = "Alpha.\n\n\n\nBravo.\n\n\n\nCharlie.\n"
        let blocks = parser.parseDocument(source)

        XCTAssertEqual(
            MarkdownSourceEditor.replacing(
                blocks: 1...1,
                in: blocks,
                with: "",
                within: source
            ),
            "Alpha.\n\nCharlie.\n"
        )
    }

    /// cmark reports the blank line after a list as part of the list's range.
    /// Removing the following final block must not therefore leave that blank
    /// line at the end of the document.
    func testRemovingTheBlockAfterAListLeavesNoTrailingBlankLine() {
        let source = "* alpha\n* bravo\n\nTail.\n"
        let blocks = parser.parseDocument(source)

        XCTAssertEqual(
            MarkdownSourceEditor.replacing(
                blocks: 1...1,
                in: blocks,
                with: "",
                within: source
            ),
            "* alpha\n* bravo\n"
        )
    }

    func testReplacingTheFinalBlockKeepsAMissingFinalLineEnding() {
        let source = "# Title\n\nOld."
        let blocks = parser.parseDocument(source)

        XCTAssertEqual(
            MarkdownSourceEditor.replacing(
                blocks: 1...1,
                in: blocks,
                with: "New.\n",
                within: source
            ),
            "# Title\n\nNew."
        )
    }

    func testReplacingUsesTheDocumentsCarriageReturnLineFeeds() {
        let source = "# One\r\n\r\nOld.\r\n\r\n# Three\r\n"
        let blocks = parser.parseDocument(source)

        XCTAssertEqual(
            MarkdownSourceEditor.replacing(
                blocks: 1...1,
                in: blocks,
                with: "New.\n",
                within: source
            ),
            "# One\r\n\r\nNew.\r\n\r\n# Three\r\n"
        )
    }

    func testReplacingUsesTheDocumentsLoneCarriageReturns() {
        let source = "# One\r\rOld.\r\r# Three\r"
        let blocks = parser.parseDocument(source)

        XCTAssertEqual(
            MarkdownSourceEditor.replacing(
                blocks: 1...1,
                in: blocks,
                with: "New.\n",
                within: source
            ),
            "# One\r\rNew.\r\r# Three\r"
        )
    }

    func testInsertingAfterTheFinalBlockKeepsAMissingFinalLineEnding() throws {
        let source = "# Only"
        let block = try XCTUnwrap(parser.parseDocument(source).first)

        XCTAssertEqual(
            MarkdownSourceEditor.inserting("New.\n", after: block, in: source),
            "# Only\n\nNew."
        )
    }

    func testInsertingBetweenBlocksCollapsesWideSeparators() throws {
        let source = "Alpha.\n\n\n\nBravo.\n"
        let blocks = parser.parseDocument(source)
        let first = try XCTUnwrap(blocks.first)

        XCTAssertEqual(
            MarkdownSourceEditor.inserting(
                "Inserted.\n",
                after: first,
                in: source
            ),
            "Alpha.\n\nInserted.\n\nBravo.\n"
        )
    }

    func testInsertingAfterUsesCarriageReturnLineFeeds() throws {
        let source = "Alpha.\r\n\r\nBravo.\r\n"
        let block = try XCTUnwrap(parser.parseDocument(source).first)

        XCTAssertEqual(
            MarkdownSourceEditor.inserting("Inserted.\n", after: block, in: source),
            "Alpha.\r\n\r\nInserted.\r\n\r\nBravo.\r\n"
        )
    }

    func testInsertingAfterUsesLoneCarriageReturns() throws {
        let source = "Alpha.\r\rBravo.\r"
        let block = try XCTUnwrap(parser.parseDocument(source).first)

        XCTAssertEqual(
            MarkdownSourceEditor.inserting("Inserted.\n", after: block, in: source),
            "Alpha.\r\rInserted.\r\rBravo.\r"
        )
    }

    func testInsertingAfterPreservesATXHeadingTrailingSource() throws {
        let cases = [
            (
                "# Title   \n\nBody.\n",
                "# Title   \n\nInserted.\n\nBody.\n"
            ),
            (
                "# Title\t\n\nBody.\n",
                "# Title\t\n\nInserted.\n\nBody.\n"
            ),
            (
                "# Title #\n\nBody.\n",
                "# Title #\n\nInserted.\n\nBody.\n"
            ),
            (
                "# Title   \r\n\r\nBody.\r\n",
                "# Title   \r\n\r\nInserted.\r\n\r\nBody.\r\n"
            ),
        ]

        for (source, expected) in cases {
            let block = try XCTUnwrap(parser.parseDocument(source).first)
            XCTAssertEqual(
                MarkdownSourceEditor.inserting(
                    "Inserted.\n",
                    after: block,
                    in: source
                ),
                expected
            )
        }
    }

    func testInsertingAfterCollapsesCommonMarkWhitespaceOnlyBlankLines() throws {
        let source = "Alpha.\n \t \n\t\nBravo.\n"
        let block = try XCTUnwrap(parser.parseDocument(source).first)

        XCTAssertEqual(
            MarkdownSourceEditor.inserting("Inserted.\n", after: block, in: source),
            "Alpha.\n\nInserted.\n\nBravo.\n"
        )
    }

    func testInsertingAfterABlockPreservesUnparsedSourceThatFollows() throws {
        let source = "# Title\n\n<div>raw</div>\n\nTail.\n"
        let block = try XCTUnwrap(parser.parseDocument(source).first)

        XCTAssertEqual(
            MarkdownSourceEditor.inserting("Inserted.\n", after: block, in: source),
            "# Title\n\nInserted.\n\n<div>raw</div>\n\nTail.\n"
        )
    }

    func testReplacingABlockPreservesUnparsedSourceThatFollows() {
        let source = "# Old\n\n[ref]: /url\n\nTail.\n"
        let blocks = parser.parseDocument(source)

        XCTAssertEqual(
            MarkdownSourceEditor.replacing(
                blocks: 0...0,
                in: blocks,
                with: "# New\n",
                within: source
            ),
            "# New\n\n[ref]: /url\n\nTail.\n"
        )
    }

    func testUnicodeWhitespaceAndSeparatorsRemainRealBlocks() throws {
        let characters = [
            "\u{00A0}", "\u{2003}", "\u{3000}",
            "\u{000B}", "\u{000C}", "\u{0085}", "\u{2028}", "\u{2029}",
        ]

        for character in characters {
            let source = "Alpha.\n\n\(character)\n\nBravo.\n"
            let blocks = parser.parseDocument(source)
            XCTAssertEqual(blocks.count, 3, character.debugDescription)

            XCTAssertEqual(
                MarkdownSourceEditor.replacing(
                    blocks: 0...0,
                    in: blocks,
                    with: "",
                    within: source
                ),
                "\(character)\n\nBravo.\n",
                character.debugDescription
            )

            let first = try XCTUnwrap(blocks.first)
            XCTAssertEqual(
                MarkdownSourceEditor.inserting(
                    "Inserted.\n",
                    after: first,
                    in: source
                ),
                "Alpha.\n\nInserted.\n\n\(character)\n\nBravo.\n",
                character.debugDescription
            )
        }
    }

    /// Blank lines cannot hold an indented code block apart from the list
    /// above it, thus the plain splice would make the code a paragraph of the
    /// last item. A fence at column 0 ends the list, so the editor re-spells
    /// the code block it would otherwise lose. The code itself is unchanged.
    func testRemovalFencesIndentedCodeRatherThanLetAListAbsorbIt() {
        let source = "* alpha\n* bravo\n\n> quoted\n\n    indented code\n"
        let blocks = parser.parseDocument(source)

        XCTAssertEqual(
            MarkdownSourceEditor.replacing(
                blocks: 1...1,
                in: blocks,
                with: "",
                within: source
            ),
            "* alpha\n* bravo\n\n```\nindented code\n```\n"
        )
    }

    /// Two lists may join when an edit makes them adjacent, but that allowance
    /// belongs to the leading boundary alone. It must never excuse the code
    /// block at the trailing boundary, which is re-spelled to stay a block of
    /// its own. A result of a single list would mean the merge was spent twice.
    func testReplacementCannotSpendALeadingMergeAtTheTrailingBoundary() {
        let source = "* alpha\n\n> quoted\n\n    indented code\n"
        let blocks = parser.parseDocument(source)

        XCTAssertEqual(
            MarkdownSourceEditor.replacing(
                blocks: 1...1,
                in: blocks,
                with: "* c",
                within: source
            ),
            "* alpha\n\n* c\n\n```\nindented code\n```\n"
        )
    }

    func testRemovalAllowsTwoListsToBecomeAdjacent() {
        let source = "* a\n\nMiddle.\n\n* b\n"
        let blocks = parser.parseDocument(source)

        XCTAssertEqual(
            MarkdownSourceEditor.replacing(
                blocks: 1...1,
                in: blocks,
                with: "",
                within: source
            ),
            "* a\n\n* b\n"
        )
    }

    func testRemovalAllowsTwoIndentedCodeBlocksToJoin() {
        let source = "    code\n\nMiddle.\n\n    more\n"
        let blocks = parser.parseDocument(source)

        XCTAssertEqual(
            MarkdownSourceEditor.replacing(
                blocks: 1...1,
                in: blocks,
                with: "",
                within: source
            ),
            "    code\n\n    more\n"
        )
    }
}
