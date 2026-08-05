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

    /// The continuation sits at the content column and stays there. Four
    /// columns further is an indented code block, and every further pass adds
    /// four more.
    ///
    /// This asserts the column directly. Reading the blocks back and looking
    /// for a `.codeBlock` cannot work: `parse` returns only top level blocks,
    /// and a code block inside a list item is not one of them.
    func testTheContinuationColumnDoesNotDriftAcrossPasses() {
        let source = """
        - [ ] Ship the release

          Wait for the sign off first.

        """
        var text = source
        for pass in 1...4 {
            text = BlockFormatter.format(parser.parse(text))
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            guard let line = lines.first(where: { $0.contains("Wait for the sign off") }) else {
                return XCTFail("the continuation vanished on pass \(pass):\n\(text)")
            }
            let leadingSpaces = line.prefix { $0 == " " }.count
            XCTAssertEqual(leadingSpaces, 2, "pass \(pass) put the continuation at column \(leadingSpaces)")
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

    // MARK: - An item that is nothing but a box

    /// A checkbox is state, so an item that holds only a box is content and
    /// has to survive. Dropping it loses the box outright.
    func testAnItemThatIsOnlyABoxSurvives() {
        let source = "- [ ] Filled task\n- [ ] \n- [x] Another task\n"
        assertStable(source, source)
    }

    /// Worse than losing one line: dropping the parent leaves the child at an
    /// indent that reads back as an indented code block, which destroys the
    /// whole list.
    func testAnEmptyBoxKeepsItsSublistAttached() {
        let source = "- [ ] \n    - [x] Child task\n"
        let output = BlockFormatter.format(parser.parse(source))
        XCTAssertTrue(output.hasPrefix("- [ ] "), "the parent was dropped:\n\(output)")
        let second = BlockFormatter.format(parser.parse(output))
        XCTAssertEqual(second, output, "second pass changed the document")
    }

    // MARK: - The box means what the source said

    /// An unfinished task must not come back finished because the prose after
    /// it happens to hold a `[x]`.
    func testALaterBoxInTheTextDoesNotCheckTheItem() {
        let output = BlockFormatter.format(parser.parse("- [ ] Ship it [x] today\n"))
        XCTAssertTrue(output.hasPrefix("- [ ] "), "the box was flipped to checked:\n\(output)")
        let second = BlockFormatter.format(parser.parse(output))
        XCTAssertEqual(second, output, "second pass changed the document")
    }

    // MARK: - Normalization

    /// An uppercase box is written back lowercase. The round trip is not byte
    /// stable for `[X]`, and that is deliberate.
    func testAnUppercaseBoxIsWrittenBackLowercase() {
        let output = BlockFormatter.format(parser.parse("- [X] Ship it\n"))
        XCTAssertEqual(output, "- [x] Ship it\n")
        let second = BlockFormatter.format(parser.parse(output))
        XCTAssertEqual(second, output)
    }

    // MARK: - Plain lists

    // The continuation rule and the loose rule are not task list features.
    // They change every list, so they are tested without a checkbox too.

    func testAPlainItemKeepsItsContinuationParagraph() {
        let source = """
        - Ship the release

          Wait for the sign off first.

        """
        assertStable(source, source)
    }

    func testAPlainOrderedItemLinesUpUnderItsContent() {
        let source = """
        1. Ship the release

           Wait for the sign off first.

        """
        assertStable(source, source)
    }

    func testATightPlainListKeepsNoBlankLines() {
        assertStable("- A\n- B\n- C\n", "- A\n- B\n- C\n")
    }

    /// A list whose items are separated by blank lines is loose even when no
    /// item holds two paragraphs. This is why tightness is read from cmark
    /// rather than guessed from the item text.
    func testALooseListOfSingleParagraphItemsKeepsItsBlankLines() {
        assertStable("- A\n\n- B\n", "- A\n\n- B\n")
    }

    /// A loose sublist inside a TIGHT parent. The gap between two children
    /// must not be written in front of the FIRST child, where it would fall
    /// between the parent and its own sublist and make the parent loose. The
    /// parent would then gain a blank line, and an indent level, on every
    /// pass.
    ///
    /// `testALooseSublistLoosensItsParent` cannot catch this, because both
    /// lists are loose there and the gap is wanted either way.
    func testALooseSublistInsideATightParentIsStable() {
        let source = """
        - Parent one
            - Child A

            - Child B
        - Parent two

        """
        assertStable(source, source)
    }

    func testALooseTaskSublistInsideATightParentIsStable() {
        let source = """
        - [ ] Parent one
            - [x] Child A

            - [ ] Child B
        - [ ] Parent two

        """
        assertStable(source, source)
    }

    /// The mirror case: the gap before the first child belongs to the parent,
    /// so a loose parent keeps it even when the sublist itself is tight.
    func testATightSublistInsideALooseParentIsStable() {
        let source = """
        - Parent one

            - Child A
            - Child B

        - Parent two

        """
        assertStable(source, source)
    }

    /// An item may not stand more than one level deeper than the item before
    /// it. `- - inner` has no text on the outer item, so nothing is written at
    /// level 0 and the child would land at four spaces, which reads back as an
    /// indented code block rather than a list.
    func testAnItemNeverJumpsMoreThanOneIndentLevel() {
        let source = "- - inner child\n"
        let output = BlockFormatter.format(parser.parse(source))
        XCTAssertFalse(output.hasPrefix("    "), "the item was orphaned into a code block:\n\(output)")
        let second = BlockFormatter.format(parser.parse(output))
        XCTAssertEqual(second, output, "second pass changed the document")
    }

    /// A blank line inside the child also makes the PARENT list loose, which
    /// is cmark's rule and not a shortcut here: the blank line falls inside
    /// the parent's first item. So a blank line appears between the parent and
    /// its own child, and the output is not byte identical to the input.
    func testALooseSublistLoosensItsParent() {
        let source = """
        - Parent one
            - Child with

              a second paragraph

        - Parent two

        """
        let expected = """
        - Parent one

            - Child with

              a second paragraph

        - Parent two

        """
        assertStable(source, expected)
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
