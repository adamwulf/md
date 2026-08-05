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
}
