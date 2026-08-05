//
//  TaskListFormattingTests.swift
//  md
//
//  Created by Adam Wulf on 8/4/26.
//

import XCTest
@testable import md
@testable import MarkdownKit

/// Task list support: the checkbox survives a round trip, and a continuation
/// paragraph lines up under the item CONTENT rather than past the checkbox.
///
/// Every case asserts the exact bytes as well as idempotence. Idempotence alone
/// is not enough: a formatter that settles on a stable WRONG indent passes an
/// idempotence check while the author's prose is silently an indented code
/// block.
final class TaskListFormattingTests: XCTestCase {

    let parser = MarkdownParser()

    /// Format once, then format the result again. The two passes must agree,
    /// and the first must match `expected` byte for byte.
    private func assertStable(
        _ source: String,
        _ expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let first = BlockFormatter.format(parser.parse(source))
        XCTAssertEqual(first, expected, "first pass", file: file, line: line)

        let second = BlockFormatter.format(parser.parse(first))
        XCTAssertEqual(second, first, "second pass changed the document", file: file, line: line)
    }

    // MARK: - The checkbox is a marker, not text

    func testAnUncheckedBoxSurvivesARoundTrip() {
        assertStable("- [ ] Ship the release\n", "- [ ] Ship the release\n")
    }

    func testACheckedBoxSurvivesARoundTrip() {
        assertStable("- [x] Write the notes\n", "- [x] Write the notes\n")
    }

    func testTheCheckboxIsNotPartOfTheItemText() {
        let blocks = parser.parse("- [ ] Ship the release\n")
        guard case .list(let items, _, _, _, _) = blocks[0] else {
            return XCTFail("expected a list block")
        }
        XCTAssertEqual(items[0].text, "Ship the release")
    }

    func testAPlainItemNextToATaskItemKeepsNoBox() {
        assertStable("- [ ] A task\n- A plain item\n", "- [ ] A task\n- A plain item\n")
    }

    // MARK: - A continuation lines up under the content

    /// The heart of the bug. Content starts at column 2 for a `- ` marker, so
    /// the continuation belongs at column 2. Four columns past the content
    /// start is an indented code block, and the prose stops being prose.
    func testAContinuationParagraphLinesUpUnderTheContent() {
        let source = """
        - [ ] Ship the release

          Wait for the sign off first.

        """
        assertStable(source, source)
    }

    /// The continuation must stay a paragraph, not become a code block. Read
    /// the output back and check the block kinds rather than the bytes.
    func testAContinuationParagraphNeverBecomesACodeBlock() {
        let source = """
        - [ ] Ship the release

          Wait for the sign off first.

        """
        var text = source
        for pass in 1...4 {
            text = BlockFormatter.format(parser.parse(text))
            let blocks = parser.parse(text)
            for block in blocks {
                if case .codeBlock = block {
                    XCTFail("the continuation became a code block on pass \(pass):\n\(text)")
                    return
                }
            }
        }
    }

    /// A continuation paragraph must not be fused onto the end of the first
    /// one. `main` writes "releaseWait", which welds two words together.
    func testAContinuationParagraphIsNotFusedOntoTheFirst() {
        let source = """
        - [ ] Ship the release

          Wait for the sign off first.

        """
        let output = BlockFormatter.format(parser.parse(source))
        XCTAssertFalse(output.contains("releaseWait"), "two paragraphs were fused:\n\(output)")
    }

    /// A soft wrapped first paragraph HIDES the indent defect, because a lazy
    /// continuation line reads as paragraph text at any indentation. Kept so
    /// the shape that passes for the wrong reason is on the record.
    func testASoftWrappedTaskItemStaysOneItem() {
        let source = """
        - [ ] Ship the release
          once the sign off lands

        """
        let output = BlockFormatter.format(parser.parse(source))
        let blocks = parser.parse(output)
        XCTAssertEqual(blocks.count, 1, "the wrap split the item:\n\(output)")
        guard case .list(let items, _, _, _, _) = blocks[0] else {
            return XCTFail("expected a list block")
        }
        XCTAssertEqual(items.count, 1, "the wrap became two items:\n\(output)")
    }

    // MARK: - Sublists

    func testANestedTaskListKeepsEachBoxItOwns() {
        let source = """
        - [ ] Parent task
            - [x] Child done
            - [ ] Child open

        """
        assertStable(source, source)
    }

    func testANestedTaskListUnderAPlainParent() {
        let source = """
        - Parent item
            - [ ] Child task

        """
        assertStable(source, source)
    }

    func testATaskSublistUnderAnOrderedParent() {
        let source = """
        1. First step
            - [ ] A sub task

        """
        assertStable(source, source)
    }

    /// A checkbox belongs to the piece holding the item's FIRST paragraph and
    /// to no other. An item split by a nested list must not hand its box to
    /// the plain tail paragraph, which would claim a task nobody wrote.
    func testACheckboxDoesNotCarryPastANestedList() {
        let source = """
        - [x] Parent task
            - Child item

          A plain tail paragraph.

        """
        let output = BlockFormatter.format(parser.parse(source))
        XCTAssertFalse(
            output.contains("[x] A plain tail paragraph"),
            "a checkbox was invented on a plain paragraph:\n\(output)"
        )
    }

    // MARK: - The whole document

    func testThePlanDocumentRoundTrips() {
        let source = """
        # Plan

        - [ ] Ship the release

          Wait for the sign off first.

        - [x] Write the notes

        """
        assertStable(source, source)
    }
}
