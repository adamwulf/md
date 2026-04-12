//
//  MarkdownParserTests.swift
//  md
//
//  Created by Adam Wulf on 4/12/26.
//

import XCTest
@testable import MarkdownKit

final class MarkdownParserTests: XCTestCase {

    let parser = MarkdownParser()

    func testParseHeading() {
        let blocks = parser.parse("# Hello World")
        XCTAssertEqual(blocks.count, 1)
        if case .heading(let level, let text, _, _) = blocks[0] {
            XCTAssertEqual(level, 1)
            XCTAssertEqual(text, "Hello World")
        } else {
            XCTFail("Expected heading block")
        }
    }

    func testParseParagraph() {
        let blocks = parser.parse("This is a paragraph.")
        XCTAssertEqual(blocks.count, 1)
        if case .paragraph(let text, _, _) = blocks[0] {
            XCTAssertEqual(text, "This is a paragraph.")
        } else {
            XCTFail("Expected paragraph block")
        }
    }

    func testParseCodeBlock() {
        let markdown = """
        ```swift
        let x = 42
        ```
        """
        let blocks = parser.parse(markdown)
        XCTAssertEqual(blocks.count, 1)
        if case .codeBlock(let language, let code, _, _) = blocks[0] {
            XCTAssertEqual(language, "swift")
            XCTAssertTrue(code.contains("let x = 42"))
        } else {
            XCTFail("Expected code block")
        }
    }

    func testParseUnorderedList() {
        let markdown = """
        - Item 1
        - Item 2
        - Item 3
        """
        let blocks = parser.parse(markdown)
        XCTAssertEqual(blocks.count, 1)
        if case .list(let items, let ordered, _, _) = blocks[0] {
            XCTAssertFalse(ordered)
            XCTAssertEqual(items.count, 3)
            XCTAssertEqual(items[0].text, "Item 1")
        } else {
            XCTFail("Expected list block")
        }
    }

    func testParseMultipleBlocks() {
        let markdown = """
        # Title

        A paragraph.

        ---

        > A quote
        """
        let blocks = parser.parse(markdown)
        XCTAssertEqual(blocks.count, 4)
    }
}
