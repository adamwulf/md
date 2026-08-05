//
//  TaskListParsingTests.swift
//  md
//
//  Created by Adam Wulf on 8/4/26.
//

import XCTest
@testable import MarkdownKit

/// The checkbox reaches the model as `ListItem.task` rather than as text, and
/// it belongs to the item that carries it and to no other.
final class TaskListParsingTests: XCTestCase {

    let parser = MarkdownParser()

    private func items(
        _ source: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> [ListItem] {
        let blocks = parser.parse(source)
        for block in blocks {
            if case .list(let items, _, _, _, _) = block {
                return items
            }
        }
        XCTFail("no list block in:\n\(source)", file: file, line: line)
        return []
    }

    // MARK: - The box reaches the model

    func testAnUncheckedBoxIsUnchecked() {
        let items = items("- [ ] Ship it\n")
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.task, .unchecked)
        XCTAssertEqual(items.first?.text, "Ship it")
    }

    func testACheckedBoxIsChecked() {
        let items = items("- [x] Ship it\n")
        XCTAssertEqual(items.first?.task, .checked)
        XCTAssertEqual(items.first?.text, "Ship it")
    }

    func testAnUppercaseBoxIsChecked() {
        let items = items("- [X] Ship it\n")
        XCTAssertEqual(items.first?.task, .checked)
        XCTAssertEqual(items.first?.text, "Ship it")
    }

    func testAnItemWithNoBoxHasNoTask() {
        let items = items("- Ship it\n")
        XCTAssertNil(items.first?.task)
        XCTAssertEqual(items.first?.text, "Ship it")
    }

    /// A bracket that is text stays text. Only a box at the head of an item is
    /// a checkbox.
    /// The brackets come back escaped, because a bare `[x]` in running text
    /// would read as a link reference on the next pass. The escape is what
    /// keeps the brackets literal, so it belongs in the text.
    func testABracketInTheMiddleOfAnItemIsNotABox() {
        let items = items("- Ship it [x] today\n")
        XCTAssertNil(items.first?.task)
        XCTAssertEqual(items.first?.text, "Ship it \\[x\\] today")
    }

    /// Upstream `tasklist.c` decides "checked" with `strstr` over the whole
    /// line, so a later `[x]` in the prose flips the box and a task nobody
    /// finished comes back finished. The box is read from the source instead.
    func testALaterBoxInTheTextDoesNotCheckTheItem() {
        let items = items("- [ ] Ship it [x] today\n")
        XCTAssertEqual(items.first?.task, .unchecked)
    }

    func testALaterUppercaseBoxInTheTextDoesNotCheckTheItem() {
        let items = items("- [ ] Ship it [X] today\n")
        XCTAssertEqual(items.first?.task, .unchecked)
    }

    /// The reverse must hold too: a real checked box stays checked even when
    /// an unchecked looking pair follows it.
    func testALaterEmptyBoxInTheTextDoesNotUncheckTheItem() {
        let items = items("- [x] Ship it [ ] today\n")
        XCTAssertEqual(items.first?.task, .checked)
    }

    /// A checkbox is state, so an item that holds only a box still reaches the
    /// model. Dropping it would lose the box and orphan any nested list.
    func testAnItemThatIsOnlyABoxReachesTheModel() {
        let items = items("- [ ] \n- [x] Another task\n")
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].task, .unchecked)
        XCTAssertEqual(items[0].text, "")
        XCTAssertEqual(items[1].task, .checked)
    }

    func testAnEmptyBoxKeepsItsSublistAttached() {
        let items = items("- [ ] \n    - [x] Child task\n")
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].indentLevel, 0)
        XCTAssertEqual(items[0].task, .unchecked)
        XCTAssertEqual(items[1].indentLevel, 1)
    }

    func testATaskItemAndAPlainItemKeepTheirOwnState() {
        let items = items("- [ ] A task\n- A plain item\n")
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].task, .unchecked)
        XCTAssertNil(items[1].task)
    }

    // MARK: - Sublists

    func testANestedTaskItemCarriesItsOwnBox() {
        let items = items("- [ ] Parent\n    - [x] Child\n")
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].task, .unchecked)
        XCTAssertEqual(items[0].indentLevel, 0)
        XCTAssertEqual(items[1].task, .checked)
        XCTAssertEqual(items[1].indentLevel, 1)
    }

    func testATaskItemNestsUnderAPlainParent() {
        let items = items("- Parent\n    - [ ] Child\n")
        XCTAssertNil(items[0].task)
        XCTAssertEqual(items[1].task, .unchecked)
    }

    func testThreeLevelsOfNestingEachKeepTheirOwnBox() {
        let source = """
        - [ ] One
            - [x] Two
                - [ ] Three

        """
        let items = items(source)
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items.map(\.indentLevel), [0, 1, 2])
        XCTAssertEqual(items.map(\.task), [.unchecked, .checked, .unchecked])
    }

    func testATaskSublistUnderAnOrderedParent() {
        let items = items("1. First\n    - [ ] Sub task\n")
        XCTAssertNil(items[0].task)
        XCTAssertTrue(items[0].ordered)
        XCTAssertEqual(items[1].task, .unchecked)
        XCTAssertFalse(items[1].ordered)
    }

    // MARK: - The box is spent once

    /// A nested list splits its item in two. The box goes to the piece holding
    /// the first paragraph, so the tail paragraph must come back plain, or the
    /// document claims a task nobody ever wrote.
    func testTheBoxDoesNotCarryPastANestedList() {
        let source = """
        - [x] Parent task
            - Child item

          A plain tail paragraph.

        """
        let items = items(source)
        let tail = items.first { $0.text == "A plain tail paragraph." }
        XCTAssertNotNil(tail, "the tail paragraph is missing from:\n\(items.map(\.text))")
        XCTAssertNil(tail?.task, "a checkbox was invented on a plain paragraph")
    }

    // MARK: - More than one paragraph in an item

    /// Two paragraphs are joined by a blank line, never run together. Running
    /// them together welds the last word of one onto the first of the next.
    func testTwoParagraphsInAnItemKeepTheBlankLineBetweenThem() {
        let source = """
        - [ ] Ship the release

          Wait for the sign off first.

        """
        let items = items(source)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].text, "Ship the release\n\nWait for the sign off first.")
        XCTAssertEqual(items[0].task, .unchecked)
    }

    func testASoftWrapKeepsOneItemAndOneParagraph() {
        let source = """
        - [ ] Ship the release
          once the sign off lands

        """
        let items = items(source)
        XCTAssertEqual(items.count, 1)
        XCTAssertFalse(items[0].text.contains("\n\n"), "a soft wrap became two paragraphs")
    }
}
