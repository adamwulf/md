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
