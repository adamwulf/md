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

    /// A setext heading (a line of text with `===` or `---` below it) can be written
    /// on more than one line, but a heading block is written back as one ATX line
    /// (`# text`). Thus a newline in the text would divide one heading into a heading
    /// plus a paragraph. A heading is one line, thus its lines join with a space. See
    /// `FormatCommandTests.testFormatKeepsMultilineSetextHeadingAsOneBlock`.
    func testParseSetextHeadingKeepsTextOnOneLine() {
        for (markdown, expectedLevel) in [("First part\nSecond part\n===", 1), ("First part\nSecond part\n---", 2)] {
            let blocks = parser.parse(markdown)
            XCTAssertEqual(blocks.count, 1)
            if case .heading(let level, let text, _, _, _) = blocks[0] {
                XCTAssertEqual(level, expectedLevel)
                XCTAssertFalse(text.contains("\n"), "Heading text has a newline: \(text.debugDescription)")
                XCTAssertEqual(text, "First part Second part")
            } else {
                XCTFail("Expected heading block")
            }
        }
    }

    /// An inline node that spans two source lines of a setext heading also keeps its
    /// newline, because `getNodeText` renders such a node to commonmark. The heading
    /// text must stay on one line for every such node, not only for a soft break that
    /// is a direct child of the heading.
    ///
    /// A code span and a link are of interest, because a space in them is content.
    /// cmark makes the newline in them a space itself, thus the join at the heading
    /// finds no newline there and cannot double that space.
    func testParseSetextHeadingWithMultilineInlineNodeStaysOneLine() {
        let cases = [
            ("*Heading one\nHeading two*\n===========", "*Heading one Heading two*"),
            ("Heading **one\ntwo**\n===========", "Heading **one two**"),
            ("`code\nspan` tail\n===========", "`code span` tail"),
            ("[link one\nlink two](/url)\n===========", "[link one link two](/url)"),
        ]
        for (markdown, expectedText) in cases {
            let blocks = parser.parse(markdown)
            XCTAssertEqual(blocks.count, 1)
            guard case .heading(_, let text, _, _, _) = blocks[0] else {
                XCTFail("Expected heading block")
                continue
            }
            XCTAssertFalse(text.contains("\n"), "Heading holds a newline: \(text.debugDescription)")
            XCTAssertEqual(text, expectedText)
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

    func testParseParagraphKeepsSoftLineBreaks() {
        let markdown = "First line\nSecond line\nThird line"
        let blocks = parser.parse(markdown)
        XCTAssertEqual(blocks.count, 1)
        if case .paragraph(let text, _, _, _) = blocks[0] {
            XCTAssertEqual(text, "First line\nSecond line\nThird line")
        } else {
            XCTFail("Expected paragraph block")
        }
    }

    func testParseParagraphKeepsSoftLineBreaksWithInlineStyles() {
        let markdown = "First **bold** line\nSecond `code` line"
        let blocks = parser.parse(markdown)
        XCTAssertEqual(blocks.count, 1)
        if case .paragraph(let text, _, _, _) = blocks[0] {
            XCTAssertEqual(text, "First **bold** line\nSecond `code` line")
        } else {
            XCTFail("Expected paragraph block")
        }
    }

    func testParseParagraphSoftLineBreakDropsTrailingSpace() {
        // One trailing space is not a hard break, thus the space goes away with the newline.
        let blocks = parser.parse("First line \nSecond line")
        XCTAssertEqual(blocks.count, 1)
        if case .paragraph(let text, _, _, _) = blocks[0] {
            XCTAssertEqual(text, "First line\nSecond line")
        } else {
            XCTFail("Expected paragraph block")
        }
    }

    func testParseParagraphSoftLineBreakDropsLeadingIndent() {
        let blocks = parser.parse("First line\n    Second line")
        XCTAssertEqual(blocks.count, 1)
        if case .paragraph(let text, _, _, _) = blocks[0] {
            XCTAssertEqual(text, "First line\nSecond line")
        } else {
            XCTFail("Expected paragraph block")
        }
    }

    func testParseMultilineParagraphsSeparatedByBlankLines() {
        // More than one blank line still divides two paragraphs, and the blank lines
        // are not part of either paragraph.
        let blocks = parser.parse("line1\nline2\nline3\n\n\npara2")
        XCTAssertEqual(blocks.count, 2)
        if case .paragraph(let text, _, _, _) = blocks[0] {
            XCTAssertEqual(text, "line1\nline2\nline3")
        } else {
            XCTFail("Expected paragraph block")
        }
        if case .paragraph(let text, _, _, _) = blocks[1] {
            XCTAssertEqual(text, "para2")
        } else {
            XCTFail("Expected paragraph block")
        }
    }

    /// A hard line break is two or more spaces at the end of a line, or a backslash at
    /// the end of a line. Both spellings mean the same break, thus both keep the two
    /// lines apart. `getNodeText` writes the break back with the backslash.
    func testParseParagraphKeepsHardLineBreaks() {
        for markdown in ["First line  \nSecond line", "First line\\\nSecond line"] {
            let blocks = parser.parse(markdown)
            XCTAssertEqual(blocks.count, 1)
            guard case .paragraph(let text, _, _, _) = blocks[0] else {
                XCTFail("Expected paragraph block")
                continue
            }
            XCTAssertTrue(text.contains("\n"), "Hard break was dropped: \(text.debugDescription)")
        }
    }

    func testParseParagraphKeepsSoftLineBreaksWithCRLFLineEndings() {
        // cmark makes all line endings the same, thus CRLF and CR give "\n" in the
        // block text. No "\r" is left behind.
        for markdown in ["line1\r\nline2\r\nline3", "line1\rline2\rline3"] {
            let blocks = parser.parse(markdown)
            XCTAssertEqual(blocks.count, 1)
            if case .paragraph(let text, _, _, _) = blocks[0] {
                XCTAssertEqual(text, "line1\nline2\nline3")
            } else {
                XCTFail("Expected paragraph block")
            }
        }
    }

    func testParseParagraphKeepsSoftLineBreaksWithUnicode() {
        let markdown = "héllo wörld\nsecond ünicode line\n🎉 emoji line"
        let blocks = parser.parse(markdown)
        XCTAssertEqual(blocks.count, 1)
        if case .paragraph(let text, _, _, _) = blocks[0] {
            XCTAssertEqual(text, "héllo wörld\nsecond ünicode line\n🎉 emoji line")
        } else {
            XCTFail("Expected paragraph block")
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

    // MARK: - Items split by a nested list

    /// The flat array cannot hold "text, a nested list, then more text", so the
    /// tail is carried as its own entry. It is a CONTINUATION of the item, not
    /// an item, and only the entry that opens the item carries the marker.
    func testTailAfterANestedListContinuesTheItem() {
        let markdown = "- Parent\n\n    - Nested\n\n    Tail paragraph\n"
        let blocks = parser.parse(markdown)
        // Count first, and guard rather than subscript: an empty result would
        // TRAP on blocks[0] and take the whole run down with it, where a guard
        // reports one failed test and lets the rest speak.
        guard blocks.count == 1, case .list(let items, _, _, _, _) = blocks[0] else {
            return XCTFail("Expected one list block, got \(blocks.count)")
        }
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].text, "Parent")
        XCTAssertFalse(items[0].continuation)
        XCTAssertEqual(items[1].text, "Nested")
        XCTAssertEqual(items[1].indentLevel, 1)
        XCTAssertFalse(items[1].continuation)
        XCTAssertEqual(items[2].text, "Tail paragraph")
        XCTAssertTrue(items[2].continuation)
        // The tail belongs to the parent, so it stands at the parent's level.
        // Writing it one deeper would nest it under the sublist.
        XCTAssertEqual(items[2].indentLevel, 0)
    }

    /// `count` answers how many entries the array holds. `authoredCount`
    /// answers the question anyone reporting a list actually has.
    func testAuthoredCountSkipsAContinuation() {
        let markdown = "- Parent\n\n    - Nested\n\n    Tail paragraph\n"
        let blocks = parser.parse(markdown)
        guard blocks.count == 1, case .list(let items, _, _, _, _) = blocks[0] else {
            return XCTFail("Expected one list block, got \(blocks.count)")
        }
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items.authoredCount, 2)
    }

    /// The author wrote ONE box. Two nested lists split the item into three
    /// pieces, and the box must land on the first and never appear again: a
    /// checkbox on a piece that had none claims a task nobody wrote.
    func testACheckboxIsSpentOnceHoweverOftenTheItemIsSplit() {
        let markdown = """
        - [x] First

            - A

            Middle

            - B

            Tail
        """
        let blocks = parser.parse(markdown)
        guard blocks.count == 1, case .list(let items, _, _, _, _) = blocks[0] else {
            return XCTFail("Expected one list block, got \(blocks.count)")
        }
        let boxed = items.filter { $0.task != nil }
        XCTAssertEqual(boxed.count, 1)
        XCTAssertEqual(boxed.first?.text, "First")
        XCTAssertEqual(boxed.first?.task, .checked)
        // Both tails continue the item, and neither carries a box.
        let continuations = items.filter { $0.continuation }
        XCTAssertEqual(continuations.map(\.text), ["Middle", "Tail"])
        XCTAssertTrue(continuations.allSatisfy { $0.task == nil })
    }

    /// An item with no nested list is not split at all, so nothing in it is a
    /// continuation. Two paragraphs live in one item's text.
    func testAnUnsplitItemHasNoContinuation() {
        let markdown = "- Parent\n\n  Second paragraph\n\n- Sibling\n"
        let blocks = parser.parse(markdown)
        guard blocks.count == 1, case .list(let items, _, _, _, _) = blocks[0] else {
            return XCTFail("Expected one list block, got \(blocks.count)")
        }
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.authoredCount, 2)
        XCTAssertEqual(items[0].text, "Parent\n\nSecond paragraph")
        XCTAssertTrue(items.allSatisfy { !$0.continuation })
    }

    /// An item the author wrote empty has no children, which is how it is told
    /// apart from a mid-item flush that gathered nothing. Drop it and a bullet
    /// leaves the document.
    func testAnEmptyItemSurvives() {
        let blocks = parser.parse("- One\n- \n- Three\n")
        guard blocks.count == 1, case .list(let items, _, _, _, _) = blocks[0] else {
            return XCTFail("Expected one list block, got \(blocks.count)")
        }
        XCTAssertEqual(items.map(\.text), ["One", "", "Three"])
        XCTAssertEqual(items.authoredCount, 3)
        // It is an item in its own right, not a continuation of "One".
        XCTAssertTrue(items.allSatisfy { !$0.continuation })
    }

    func testParseNestedListItemsKeepSoftLineBreaks() {
        let markdown = "- a\n  a2\n    - b\n      b2\n        - c\n          c2"
        let blocks = parser.parse(markdown)
        XCTAssertEqual(blocks.count, 1)
        if case .list(let items, _, _, _, _) = blocks[0] {
            XCTAssertEqual(items.count, 3)
            XCTAssertEqual(items[0].text, "a\na2")
            XCTAssertEqual(items[0].indentLevel, 0)
            XCTAssertEqual(items[1].text, "b\nb2")
            XCTAssertEqual(items[1].indentLevel, 1)
            XCTAssertEqual(items[2].text, "c\nc2")
            XCTAssertEqual(items[2].indentLevel, 2)
        } else {
            XCTFail("Expected list block")
        }
    }

    /// A list item can hold more than one paragraph, and the two must not run together
    /// as one word. A blockquote has the same shape and still loses its paragraph
    /// break: see `testParseBlockquoteWithTwoParagraphsKeepsThemApart`.
    func testParseListItemWithTwoParagraphsKeepsThemApart() {
        let blocks = parser.parse("- para one\n\n  para two")
        XCTAssertEqual(blocks.count, 1)
        guard case .list(let items, _, _, _, _) = blocks[0] else {
            XCTFail("Expected list block")
            return
        }
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].text, "para one\n\npara two")
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

    /// A lazy continuation line (a line with no `>` below a quoted line) is part of
    /// the same paragraph of the blockquote, thus it keeps its soft line break.
    func testParseBlockquoteKeepsSoftLineBreaks() {
        let blocks = parser.parse("> First line\n> Second line")
        XCTAssertEqual(blocks.count, 1)
        if case .blockquote(let text, _, _, _) = blocks[0] {
            XCTAssertEqual(text, "First line\nSecond line")
        } else {
            XCTFail("Expected blockquote block")
        }
    }

    func testParseBlockquoteWithLazyContinuationKeepsSoftLineBreak() {
        let blocks = parser.parse("> line1\nline2")
        XCTAssertEqual(blocks.count, 1)
        if case .blockquote(let text, _, _, _) = blocks[0] {
            XCTAssertEqual(text, "line1\nline2")
        } else {
            XCTFail("Expected blockquote")
        }
    }

    /// KNOWN FAILURE, kept as documentation for a later fix.
    ///
    /// A blockquote can hold more than one paragraph. `getChildrenText` puts the text
    /// of each paragraph one after the other, and `getNodeText` trims the commonmark
    /// that it renders for each one. Thus no separator stays between them and the last
    /// word of the first paragraph touches the first word of the second.
    ///
    /// This is the same loss as the soft break bug, but between two blocks and not
    /// inside one, thus the soft break fix does not correct it. The fix must keep the
    /// two paragraphs apart. How many newlines to put between them is for that fix to
    /// decide, thus this test only asks for a line break. Remove the
    /// `XCTExpectFailure` when the fix is in.
    func testParseBlockquoteWithTwoParagraphsKeepsThemApart() {
        let blocks = parser.parse("> para one\n>\n> para two")
        XCTAssertEqual(blocks.count, 1)
        guard case .blockquote(let text, _, _, _) = blocks[0] else {
            XCTFail("Expected blockquote")
            return
        }
        XCTExpectFailure("Two paragraphs of a blockquote are joined with no separator") {
            XCTAssertTrue(text.contains("\n"), "The two paragraphs ran together: \(text.debugDescription)")
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

    /// A paragraph written on more than one line covers all of its lines. `md blocks`
    /// prints this range as `paragraph L1-L3`, thus the range must not stop at the
    /// first line.
    func testMultiLineParagraphLineRange() {
        let markdown = "line1\nline2\nline3\n\npara2"
        let blocks = parser.parse(markdown)
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0].lineRange, 1...3)
        XCTAssertEqual(blocks[1].lineRange, 5...5)
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

    func testCRLFByteAndCharacterRangesMatchSource() throws {
        let markdown = "# One\r\n\r\n# Two\r\n"
        let blocks = parser.parse(markdown)
        XCTAssertEqual(blocks.count, 2)

        let utf8 = Array(markdown.utf8)
        let nsString = markdown as NSString
        let expected = ["# One", "# Two"]

        for (block, expectedSource) in zip(blocks, expected) {
            let byteRange = block.byteRange
            let bytes = utf8[
                byteRange.location..<(byteRange.location + byteRange.length)
            ]
            XCTAssertEqual(String(decoding: bytes, as: UTF8.self), expectedSource)
            XCTAssertEqual(nsString.substring(with: block.charRange), expectedSource)
        }
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
