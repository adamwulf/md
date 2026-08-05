//
//  EscapedMarkdownRoundTripTests.swift
//  md
//
//  Created by Adam Wulf on 8/4/26.
//

import XCTest
@testable import md
@testable import MarkdownKit

/// `md format`, `md replace -i`, `md insert-after -i`, `md insert-before -i` and
/// `md remove -i` all write every block of the file through `BlockFormatter`, and not
/// only the block that the user asked for. Thus a block that loses its backslash
/// escapes damages the file on any of those commands.
///
/// The worst cases change the type of the block: a paragraph becomes a heading, a
/// list, or a block quote. That moves the number of blocks, thus every block index
/// after it moves too, and a later `md replace N` writes over the wrong block.
///
/// `MarkdownEscapeTests` covers the same bug at the parser.
final class EscapedMarkdownRoundTripTests: XCTestCase {

    let parser = MarkdownParser()

    // MARK: - Helpers

    /// Run the body of `md format` on in-memory content.
    private func runFormat(_ content: String) -> String {
        return FormatCommand.format(content: content, targetFrontmatter: nil)
    }

    /// The number of blocks, and the text of each one, must be the same before and
    /// after a write. This is the one rule that every case here obeys.
    private func assertSurvivesAWrite(
        _ source: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let before = parser.parse(source)
        let output = BlockFormatter.format(before)
        let after = parser.parse(output)

        XCTAssertEqual(
            after.count,
            before.count,
            "the number of blocks moved for \(source.debugDescription): \(output.debugDescription)",
            file: file,
            line: line
        )
        XCTAssertEqual(
            EscapeCases.describe(after),
            EscapeCases.describe(before),
            "the text moved for \(source.debugDescription): \(output.debugDescription)",
            file: file,
            line: line
        )
    }

    // MARK: - Every case survives a write

    func testEveryEscapeCaseSurvivesAWrite() {
        for source in EscapeCases.all {
            assertSurvivesAWrite(source)
        }
    }

    /// A second `md format` must give the same file as the first one. If it does not,
    /// the file keeps changing every time a command touches it.
    func testFormatIsIdempotentForEveryEscapeCase() {
        for source in EscapeCases.all {
            let once = runFormat(source + "\n")
            let twice = runFormat(once)
            XCTAssertEqual(twice, once, "md format is not idempotent for \(source.debugDescription)")
        }
    }

    // MARK: - The four that change the type of the block

    /// Each of these four is one paragraph. After a write each one must still be one
    /// paragraph, and not a heading, a list, or a block quote.
    func testInertBlockMarkersStayInertAfterAWrite() {
        for source in ["\\# not a heading", "\\- not a list", "\\* not emphasis \\*", "\\> not a quote"] {
            let output = runFormat(source + "\n")
            let blocks = parser.parse(output)
            XCTAssertEqual(blocks.count, 1, "expected one block for \(source.debugDescription): \(output.debugDescription)")
            guard case .paragraph = blocks.first else {
                XCTFail("expected a paragraph for \(source.debugDescription), got: \(output.debugDescription)")
                continue
            }
        }
    }

    /// The real damage: a block that grows or divides moves every index after it. Here
    /// block 3 is the one the user wants, both before and after the write.
    func testBlockIndicesDoNotMoveAfterAWrite() {
        let source = """
            # Title

            \\# not a heading

            The third block.
            """
        let before = parser.parse(source)
        XCTAssertEqual(before.count, 3)

        let after = parser.parse(runFormat(source + "\n"))
        XCTAssertEqual(after.count, 3, "the number of blocks moved, thus block 3 is no longer block 3")
        XCTAssertEqual(EscapeCases.describe(after), EscapeCases.describe(before))
    }

    // MARK: - Sources that must come back character for character

    /// For these the escape that the source uses is the same escape that the writer
    /// gives, thus the file does not change at all.
    func testTheseSourcesComeBackCharacterForCharacter() {
        let sources = [
            "\\# not a heading",
            "\\- not a list",
            "\\* not emphasis \\*",
            "\\> not a quote",
            "\\+ not a list",
            "1\\. not a list",
            "C:\\\\path\\\\file",
            "a \\_b\\_ c",
            "\\`not code\\`",
            "a *b* c",
            "a `code` c",
            "a [link](url) c",
            "a ~~strike~~ c",
            "snake_case_name here",
            "a < b and x <= y",
            "issue #42 is open",
            "text with | pipe",
            "a - b",
            "2 + 2 = 4",
            "5 \\* 3 = 15",
            "AT&T and R&D",
            "I <3 this",
        ]
        for source in sources {
            XCTAssertEqual(runFormat(source + "\n"), source + "\n", "the file changed for \(source.debugDescription)")
        }
    }

    // MARK: - Tables

    /// A `|` inside a cell must not divide the cell, thus the table keeps its shape
    /// and its text.
    func testTableCellPipeSurvivesAWrite() {
        let source = "| a \\| b | c |\n| --- | --- |\n| d | e |\n"
        let output = runFormat(source)
        guard let block = parser.parse(output).first, case .table(let rows, _, _, _) = block else {
            XCTFail("expected a table, got: \(output.debugDescription)")
            return
        }
        XCTAssertEqual(rows, [["a \\| b", "c"], ["d", "e"]])
        XCTAssertEqual(runFormat(output), output, "md format is not idempotent for a cell with a pipe")
    }

    // MARK: - Headings

    /// A run of `#` at the end of a heading line is the closing sequence of the
    /// heading, thus it is removed on the next read. The text of the heading must not
    /// lose that `#`.
    func testHeadingTrailingHashSurvivesAWrite() {
        let source = "# sharp \\#\n"
        let output = runFormat(source)
        guard let block = parser.parse(output).first, case .heading(_, let text, _, _, _) = block else {
            XCTFail("expected a heading, got: \(output.debugDescription)")
            return
        }
        XCTAssertEqual(text, "sharp \\#")
    }

    // MARK: - Lists and block quotes

    /// These two already work today. They guard the fix against a change that escapes
    /// text twice: `\\-` in a list item must not become `\\\\-`.
    func testListAndBlockquoteEscapesSurviveAWrite() {
        assertSurvivesAWrite("- \\- not a nested list")
        assertSurvivesAWrite("> \\# not a heading")
        XCTAssertEqual(runFormat("- \\- not a nested list\n"), "- \\- not a nested list\n")
        XCTAssertEqual(runFormat("> \\# not a heading\n"), "> \\# not a heading\n")
    }

    // MARK: - A whole document

    /// One document with every kind of block, to show that the fix holds when the
    /// blocks are written one after the other.
    func testWholeDocumentSurvivesAWrite() {
        let source = """
            # A \\# heading

            \\# not a heading

            - \\- not a nested list
            - a real item

            > \\> not a nested quote

            | a \\| b | c |
            | --- | --- |
            | d | e |

            ```swift
            let x = "\\# still code"
            ```

            The \\*last\\* paragraph with C:\\\\path.

            """
        assertSurvivesAWrite(source)
        let once = runFormat(source)
        XCTAssertEqual(runFormat(once), once, "md format is not idempotent for the whole document")
    }

    // MARK: - Code blocks must not change

    /// The text of a code block is verbatim, thus no escape belongs in it.
    func testCodeBlockTextIsNotEscaped() {
        let source = "```\n\\# not escaped again\nC:\\\\path\n```\n"
        XCTAssertEqual(runFormat(source), source)
    }
}
