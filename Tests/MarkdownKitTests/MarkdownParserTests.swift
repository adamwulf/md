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

    // MARK: - Headings

    func testParseHeading() {
        let blocks = parser.parse("# Hello World")
        XCTAssertEqual(blocks.count, 1)
        if case .heading(let level, let text, _, _, _) = blocks[0] {
            XCTAssertEqual(level, 1)
            XCTAssertEqual(text, "Hello World")
        } else {
            XCTFail("Expected heading block")
        }
    }

    func testParseHeadingLevels() {
        let markdown = "# H1\n\n## H2\n\n### H3\n\n#### H4\n\n##### H5\n\n###### H6"
        let blocks = parser.parse(markdown)
        XCTAssertEqual(blocks.count, 6)
        for (i, block) in blocks.enumerated() {
            if case .heading(let level, _, _, _, _) = block {
                XCTAssertEqual(level, i + 1)
            } else {
                XCTFail("Expected heading at index \(i)")
            }
        }
    }

    // MARK: - Paragraphs

    func testParseParagraph() {
        let blocks = parser.parse("This is a paragraph.")
        XCTAssertEqual(blocks.count, 1)
        if case .paragraph(let text, _, _, _) = blocks[0] {
            XCTAssertEqual(text, "This is a paragraph.")
        } else {
            XCTFail("Expected paragraph block")
        }
    }

    func testParseMultipleParagraphs() {
        let markdown = "First paragraph.\n\nSecond paragraph."
        let blocks = parser.parse(markdown)
        XCTAssertEqual(blocks.count, 2)
        if case .paragraph(let text, _, _, _) = blocks[0] {
            XCTAssertEqual(text, "First paragraph.")
        } else {
            XCTFail("Expected paragraph")
        }
        if case .paragraph(let text, _, _, _) = blocks[1] {
            XCTAssertEqual(text, "Second paragraph.")
        } else {
            XCTFail("Expected paragraph")
        }
    }

    // MARK: - Code Blocks

    func testParseCodeBlock() {
        let markdown = """
        ```swift
        let x = 42
        ```
        """
        let blocks = parser.parse(markdown)
        XCTAssertEqual(blocks.count, 1)
        if case .codeBlock(let language, let code, _, _, _) = blocks[0] {
            XCTAssertEqual(language, "swift")
            XCTAssertTrue(code.contains("let x = 42"))
        } else {
            XCTFail("Expected code block")
        }
    }

    func testParseCodeBlockNoLanguage() {
        let markdown = "```\nhello\n```"
        let blocks = parser.parse(markdown)
        XCTAssertEqual(blocks.count, 1)
        if case .codeBlock(let language, let code, _, _, _) = blocks[0] {
            XCTAssertEqual(language, "")
            XCTAssertTrue(code.contains("hello"))
        } else {
            XCTFail("Expected code block")
        }
    }

    // MARK: - Lists

    func testParseUnorderedList() {
        let markdown = """
        - Item 1
        - Item 2
        - Item 3
        """
        let blocks = parser.parse(markdown)
        XCTAssertEqual(blocks.count, 1)
        if case .list(let items, let ordered, _, _, _) = blocks[0] {
            XCTAssertFalse(ordered)
            XCTAssertEqual(items.count, 3)
            XCTAssertEqual(items[0].text, "Item 1")
            XCTAssertEqual(items[1].text, "Item 2")
            XCTAssertEqual(items[2].text, "Item 3")
        } else {
            XCTFail("Expected list block")
        }
    }

    func testParseOrderedList() {
        let markdown = "1. First\n2. Second\n3. Third"
        let blocks = parser.parse(markdown)
        XCTAssertEqual(blocks.count, 1)
        if case .list(let items, let ordered, _, _, _) = blocks[0] {
            XCTAssertTrue(ordered)
            XCTAssertEqual(items.count, 3)
            XCTAssertEqual(items[0].text, "First")
        } else {
            XCTFail("Expected ordered list")
        }
    }

    func testParseNestedList() {
        let markdown = "- Parent\n    - Child\n        - Grandchild"
        let blocks = parser.parse(markdown)
        XCTAssertEqual(blocks.count, 1)
        if case .list(let items, _, _, _, _) = blocks[0] {
            XCTAssertEqual(items.count, 3)
            XCTAssertEqual(items[0].indentLevel, 0)
            XCTAssertEqual(items[1].indentLevel, 1)
            XCTAssertEqual(items[2].indentLevel, 2)
        } else {
            XCTFail("Expected list block")
        }
    }

    // MARK: - Blockquotes

    func testParseBlockquote() {
        let blocks = parser.parse("> This is a quote")
        XCTAssertEqual(blocks.count, 1)
        if case .blockquote(let text, _, _, _) = blocks[0] {
            XCTAssertEqual(text, "This is a quote")
        } else {
            XCTFail("Expected blockquote")
        }
    }

    // MARK: - Thematic Breaks

    func testParseThematicBreak() {
        let markdown = "Above\n\n---\n\nBelow"
        let blocks = parser.parse(markdown)
        XCTAssertEqual(blocks.count, 3)
        if case .thematicBreak(_, _, _) = blocks[1] {
            // pass
        } else {
            XCTFail("Expected thematic break")
        }
    }

    // MARK: - Tables

    func testParseTable() {
        let markdown = "| A | B |\n| --- | --- |\n| 1 | 2 |"
        let blocks = parser.parse(markdown)
        XCTAssertEqual(blocks.count, 1)
        if case .table(let rows, _, _, _) = blocks[0] {
            XCTAssertEqual(rows.count, 2) // header + 1 data row
            XCTAssertEqual(rows[0], ["A", "B"])
            XCTAssertEqual(rows[1], ["1", "2"])
        } else {
            XCTFail("Expected table block")
        }
    }

    // MARK: - Line Ranges

    func testHeadingLineRange() {
        let markdown = "# Title\n\nParagraph\n\n## Subtitle"
        let blocks = parser.parse(markdown)
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[0].lineRange, 1...1)
        XCTAssertEqual(blocks[1].lineRange, 3...3)
        XCTAssertEqual(blocks[2].lineRange, 5...5)
    }

    func testCodeBlockLineRange() {
        let markdown = "# Title\n\n```swift\nlet x = 1\nlet y = 2\n```"
        let blocks = parser.parse(markdown)
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[1].lineRange, 3...6)
    }

    func testMultiLineListRange() {
        let markdown = "- A\n- B\n- C"
        let blocks = parser.parse(markdown)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].lineRange, 1...3)
    }

    // MARK: - Byte and Char Ranges

    func testByteRangeNonEmpty() {
        let blocks = parser.parse("# Hello")
        XCTAssertEqual(blocks.count, 1)
        XCTAssertGreaterThan(blocks[0].byteRange.length, 0)
    }

    func testCharRangeNonEmpty() {
        let blocks = parser.parse("# Hello")
        XCTAssertEqual(blocks.count, 1)
        XCTAssertGreaterThan(blocks[0].charRange.length, 0)
    }

    // MARK: - Multiple Block Types

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

    func testParseMixedContent() {
        let markdown = """
        # Title

        Some text.

        - Item 1
        - Item 2

        ```python
        print("hello")
        ```

        > A quote

        ---

        | Col1 | Col2 |
        | --- | --- |
        | A | B |
        """
        let blocks = parser.parse(markdown)
        XCTAssertEqual(blocks.count, 7)

        if case .heading(_, _, _, _, _) = blocks[0] {} else { XCTFail("Expected heading") }
        if case .paragraph(_, _, _, _) = blocks[1] {} else { XCTFail("Expected paragraph") }
        if case .list(_, _, _, _, _) = blocks[2] {} else { XCTFail("Expected list") }
        if case .codeBlock(_, _, _, _, _) = blocks[3] {} else { XCTFail("Expected code block") }
        if case .blockquote(_, _, _, _) = blocks[4] {} else { XCTFail("Expected blockquote") }
        if case .thematicBreak(_, _, _) = blocks[5] {} else { XCTFail("Expected thematic break") }
        if case .table(_, _, _, _) = blocks[6] {} else { XCTFail("Expected table") }
    }

    // MARK: - Edge Cases

    func testEmptyInput() {
        let blocks = parser.parse("")
        XCTAssertEqual(blocks.count, 0)
    }

    func testWhitespaceOnlyInput() {
        let blocks = parser.parse("   \n\n   \n")
        XCTAssertEqual(blocks.count, 0)
    }

    func testUnicodeContent() {
        let blocks = parser.parse("# Héllo Wörld 🌍")
        XCTAssertEqual(blocks.count, 1)
        if case .heading(_, let text, _, _, _) = blocks[0] {
            XCTAssertEqual(text, "Héllo Wörld 🌍")
        } else {
            XCTFail("Expected heading")
        }
    }

    func testInlineFormatting() {
        let blocks = parser.parse("This has **bold** and *italic* text.")
        XCTAssertEqual(blocks.count, 1)
        if case .paragraph(let text, _, _, _) = blocks[0] {
            XCTAssertTrue(text.contains("bold"))
            XCTAssertTrue(text.contains("italic"))
        } else {
            XCTFail("Expected paragraph")
        }
    }
}
