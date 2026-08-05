//
//  MarkdownEscapeTests.swift
//  md
//
//  Created by Adam Wulf on 8/4/26.
//

import XCTest
@testable import MarkdownKit

/// A backslash in the source makes a markdown marker inert: `\#` is the character `#`
/// and not a heading marker.
///
/// The text of a block is markdown source, not plain text. An emphasis node comes back
/// as `*text*`, a link node comes back as `[text](url)`, and a code span comes back as
/// `` `text` ``. Thus an inert marker must come back with its backslash. If the
/// backslash is lost, the marker becomes live markdown as soon as the block is written
/// back to a file, and the block divides, or changes its type.
///
/// See `EscapedMarkdownRoundTripTests` for what that does to a file.
final class MarkdownEscapeTests: XCTestCase {

    let parser = MarkdownParser()

    // MARK: - Helpers

    /// The text of the first block, when that block is a paragraph.
    private func paragraphText(_ source: String, file: StaticString = #filePath, line: UInt = #line) -> String {
        let blocks = parser.parse(source)
        guard blocks.count == 1, case .paragraph(let text, _, _, _) = blocks[0] else {
            XCTFail("Expected one paragraph for \(source.debugDescription)", file: file, line: line)
            return ""
        }
        return text
    }

    /// The text of the first block, when that block is a heading.
    private func headingText(_ source: String, file: StaticString = #filePath, line: UInt = #line) -> String {
        let blocks = parser.parse(source)
        guard blocks.count == 1, case .heading(_, let text, _, _, _) = blocks[0] else {
            XCTFail("Expected one heading for \(source.debugDescription)", file: file, line: line)
            return ""
        }
        return text
    }

    // MARK: - Block markers at the start of a line

    /// These four are the worst cases. Each one changes the type of the block when the
    /// escape is lost, thus `md format` alone changes what the file means.
    func testParagraphKeepsEscapedBlockMarkers() {
        XCTAssertEqual(paragraphText("\\# not a heading"), "\\# not a heading")
        XCTAssertEqual(paragraphText("\\- not a list"), "\\- not a list")
        XCTAssertEqual(paragraphText("\\* not emphasis \\*"), "\\* not emphasis \\*")
        XCTAssertEqual(paragraphText("\\> not a quote"), "\\> not a quote")
    }

    func testParagraphKeepsMoreEscapedBlockMarkers() {
        XCTAssertEqual(paragraphText("\\+ not a list"), "\\+ not a list")
        XCTAssertEqual(paragraphText("\\=== not a heading"), "\\=== not a heading")
        XCTAssertEqual(paragraphText("\\--- not a break"), "\\--- not a break")
    }

    /// An ordered list marker is a number, thus the escape goes on the `.` or the `)`.
    func testParagraphKeepsEscapedOrderedListMarker() {
        XCTAssertEqual(paragraphText("1\\. not a list"), "1\\. not a list")
        XCTAssertEqual(paragraphText("1\\) not a list"), "1\\) not a list")
    }

    /// A marker in the middle of a line does nothing, thus it needs no backslash and
    /// must not get one. Text that reads well must stay text that reads well.
    func testMidLineMarkersStayPlain() {
        XCTAssertEqual(paragraphText("a - b"), "a - b")
        XCTAssertEqual(paragraphText("issue #42 is open"), "issue #42 is open")
        XCTAssertEqual(paragraphText("arrow a -> b"), "arrow a -> b")
        XCTAssertEqual(paragraphText("2 + 2 = 4"), "2 + 2 = 4")
    }

    // MARK: - Inline markers

    func testParagraphKeepsEscapedInlineMarkers() {
        XCTAssertEqual(paragraphText("a \\_b\\_ c"), "a \\_b\\_ c")
        XCTAssertEqual(paragraphText("a \\`not code\\` c"), "a \\`not code\\` c")
        XCTAssertEqual(paragraphText("a \\~\\~not strike\\~\\~ c"), "a \\~\\~not strike\\~\\~ c")
        XCTAssertEqual(paragraphText("a \\*not emphasis\\* c"), "a \\*not emphasis\\* c")
    }

    /// A `[` can open a link, thus it keeps its backslash. A `]` alone can open
    /// nothing, thus it does not need one.
    func testParagraphKeepsEscapedLinkBracket() {
        XCTAssertEqual(paragraphText("\\[not a link\\]"), "\\[not a link]")
    }

    /// A `!` before a `[` makes an image, thus that `!` keeps its backslash.
    func testParagraphKeepsEscapedImageMarker() {
        XCTAssertEqual(paragraphText("\\!\\[not an image\\](url)"), "\\!\\[not an image](url)")
    }

    /// Here the `!` is text and the `[link](url)` is a real link node. Written together
    /// with no backslash they make an image, thus the `!` keeps its backslash.
    func testParagraphKeepsEscapedBangBeforeRealLink() {
        XCTAssertEqual(paragraphText("\\![link](url)"), "\\![link](url)")
    }

    /// A `<` can open an autolink or an HTML tag, thus it keeps its backslash.
    func testParagraphKeepsEscapedAngleBracket() {
        XCTAssertEqual(paragraphText("\\<https://example.com\\>"), "\\<https://example.com>")
        XCTAssertEqual(paragraphText("\\<div\\>text\\</div\\>"), "\\<div>text\\</div>")
    }

    /// A `<` that opens nothing must stay plain, thus arithmetic and arrows read well.
    func testInertAngleBracketStaysPlain() {
        XCTAssertEqual(paragraphText("a < b and x <= y"), "a < b and x <= y")
        XCTAssertEqual(paragraphText("count < 10"), "count < 10")
    }

    /// An underscore between two letters or numbers does nothing in markdown, thus a
    /// name such as `snake_case_name` must stay as it is.
    func testUnderscoreInsideAWordStaysPlain() {
        XCTAssertEqual(paragraphText("snake_case_name here"), "snake_case_name here")
        XCTAssertEqual(paragraphText("file_1_of_2"), "file_1_of_2")
    }

    // MARK: - The backslash itself

    /// Two backslashes in the source are one backslash of text. That backslash must
    /// come back as two, or a Windows path loses a level on every write.
    func testParagraphKeepsLiteralBackslash() {
        XCTAssertEqual(paragraphText("C:\\\\path\\\\file"), "C:\\\\path\\\\file")
    }

    // MARK: - Trade-offs that this design makes on purpose

    /// `*`, `` ` ``, `~` and `[` get a backslash everywhere, and not only where they
    /// do damage today. Each of the four needs a second character to make markup, and
    /// that second character can be in a different node of the same block. The parser
    /// gives one node at a time, thus it cannot see the pair.
    ///
    /// A backslash that a character does not need is safe: a reader shows `\*` as `*`.
    /// A pair that keeps no backslash is not safe: it changes what the text means.
    /// Thus these four take the safe side, and the source grows a backslash that the
    /// reader never shows.
    ///
    /// The three tests below hold that decision. Change them together with
    /// `MarkdownEscaper` if the decision changes.
    func testStarAlwaysKeepsABackslash() {
        // `a*b*c` is emphasis, thus a star is live between two letters as well.
        XCTAssertEqual(paragraphText("5 \\* 3 = 15"), "5 \\* 3 = 15")
        XCTAssertEqual(paragraphText("2 \\* 3 \\* 4"), "2 \\* 3 \\* 4")
    }

    func testTildeAlwaysKeepsABackslash() {
        // `~text~` is strikethrough in GFM, thus one tilde is enough to begin it.
        XCTAssertEqual(paragraphText("path ~/Documents/file"), "path \\~/Documents/file")
    }

    func testOpeningSquareBracketAlwaysKeepsABackslash() {
        // `[a](b)` is a link and `[a]` alone is a link when the file holds a
        // definition for `a`. A `]` alone opens nothing, thus it keeps no backslash.
        XCTAssertEqual(paragraphText("array[0] and array[1]"), "array\\[0] and array\\[1]")
    }

    func testBacktickAlwaysKeepsABackslash() {
        XCTAssertEqual(paragraphText("a \\` here"), "a \\` here")
    }

    // MARK: - Character entities

    /// `&amp;amp;` is the text `&amp;`. Written with no backslash it reads back as `&`,
    /// thus the `&` keeps its backslash when a name can follow it.
    func testParagraphKeepsEntityAmpersand() {
        XCTAssertEqual(paragraphText("&amp;amp; literal"), "\\&amp; literal")
    }

    /// An `&` with a space after it starts no entity, thus it stays plain.
    func testPlainAmpersandStaysPlain() {
        XCTAssertEqual(paragraphText("100% & more"), "100% & more")
    }

    // MARK: - Live markup must not get a second escape

    /// Emphasis, links, code spans and strikethrough already come back as markdown
    /// source. A second escape would turn each one into plain text.
    func testLiveInlineMarkupStaysLive() {
        XCTAssertEqual(paragraphText("a *b* c"), "a *b* c")
        XCTAssertEqual(paragraphText("a **b** c"), "a **b** c")
        XCTAssertEqual(paragraphText("a `code` c"), "a `code` c")
        XCTAssertEqual(paragraphText("a [link](url) c"), "a [link](url) c")
        XCTAssertEqual(paragraphText("a ![img](url) c"), "a ![img](url) c")
        XCTAssertEqual(paragraphText("a ~~strike~~ c"), "a ~~strike~~ c")
        XCTAssertEqual(paragraphText("a <https://example.com> c"), "a <https://example.com> c")
    }

    /// Text before and after live markup still needs its own escapes.
    func testEscapedTextAroundLiveMarkupKeepsItsEscapes() {
        XCTAssertEqual(paragraphText("\\# start *em* \\# end"), "\\# start *em* # end")
        XCTAssertEqual(paragraphText("\\[a\\] *b* \\[c\\]"), "\\[a] *b* \\[c]")
    }

    // MARK: - Headings

    /// A run of `#` at the end of a heading line is the closing sequence of the
    /// heading, and it is removed. Thus a `#` that ends the text of a heading keeps
    /// its backslash.
    func testHeadingKeepsEscapedTrailingHash() {
        XCTAssertEqual(headingText("# sharp \\#"), "sharp \\#")
        XCTAssertEqual(headingText("## grade \\##"), "grade \\##")
    }

    /// Here the same `#` is both the first character of the line and the run of `#` at
    /// the end of the line. Two rules point at it, and it must still get one backslash
    /// and not two.
    func testHeadingOfOneHashGetsOneBackslash() {
        XCTAssertEqual(headingText("# \\#"), "\\#")
    }

    func testHeadingKeepsEscapedMarkers() {
        XCTAssertEqual(headingText("# a \\*star\\* here"), "a \\*star\\* here")
        XCTAssertEqual(headingText("# C:\\\\path"), "C:\\\\path")
    }

    // MARK: - Table cells

    /// A `|` divides one cell from the next, thus a `|` inside a cell keeps its
    /// backslash. Without it the row grows a cell on every write.
    func testTableCellKeepsEscapedPipe() {
        let blocks = parser.parse("| a \\| b | c |\n| --- | --- |\n| d | e |")
        guard blocks.count == 1, case .table(let rows, _, _, _) = blocks[0] else {
            XCTFail("Expected one table")
            return
        }
        XCTAssertEqual(rows, [["a \\| b", "c"], ["d", "e"]])
    }

    /// A `|` outside a table divides nothing, thus a paragraph keeps it plain.
    func testParagraphPipeStaysPlain() {
        XCTAssertEqual(paragraphText("text with | pipe"), "text with | pipe")
    }

    // MARK: - Lists and block quotes

    /// A list item and a block quote already keep their escapes, because their text
    /// comes from a whole child block and not from one text node. These two guard that.
    func testListItemKeepsEscapes() {
        let blocks = parser.parse("- \\- not a nested list")
        guard case .list(let items, _, _, _, _) = blocks[0] else {
            XCTFail("Expected a list")
            return
        }
        XCTAssertEqual(items.map { $0.text }, ["\\- not a nested list"])
    }

    func testBlockquoteKeepsEscapes() {
        let blocks = parser.parse("> \\# not a heading")
        guard case .blockquote(let text, _, _, _) = blocks[0] else {
            XCTFail("Expected a block quote")
            return
        }
        XCTAssertEqual(text, "\\# not a heading")
    }

    // MARK: - Text that holds no marker

    /// Text with no marker in it must come back character for character, whatever
    /// letters it uses.
    func testTextWithNoMarkerIsNotTouched() {
        XCTAssertEqual(paragraphText("héllo wörld 🎉 and more"), "héllo wörld 🎉 and more")
        XCTAssertEqual(paragraphText("a plain sentence."), "a plain sentence.")
    }

    // MARK: - The escaper on its own

    /// `MarkdownEscaper` takes the text of one node. These call it directly, thus they
    /// hold its contract with no help from cmark.
    func testEscaperEscapesNothingInAnEmptyText() {
        XCTAssertEqual(MarkdownEscaper.escape("", context: .paragraph, startsLine: true), "")
    }

    func testEscaperUsesTheStartOfTheLineOnlyWhenAskedTo() {
        XCTAssertEqual(MarkdownEscaper.escape("# a", context: .paragraph, startsLine: true), "\\# a")
        XCTAssertEqual(MarkdownEscaper.escape("# a", context: .paragraph, startsLine: false), "# a")
    }

    /// A line of a paragraph can begin with spaces. The marker after them is still the
    /// first thing on the line.
    func testEscaperLooksPastSpacesAtTheStartOfALine() {
        XCTAssertEqual(MarkdownEscaper.escape("  - a", context: .paragraph, startsLine: true), "  \\- a")
    }

    /// No line begins inside a cell, thus a `#` there is text. A `|` there is not.
    func testEscaperTreatsATableCellAsOneCell() {
        XCTAssertEqual(MarkdownEscaper.escape("# a", context: .tableCell, startsLine: true), "# a")
        XCTAssertEqual(MarkdownEscaper.escape("a | b", context: .tableCell), "a \\| b")
        XCTAssertEqual(MarkdownEscaper.escape("a | b", context: .paragraph), "a | b")
    }

    /// The closing sequence of a heading is a run of `#` at the end of the line, and
    /// spaces can follow it.
    func testEscaperEscapesTheClosingHashOfAHeadingOnly() {
        XCTAssertEqual(MarkdownEscaper.escape("a #", context: .heading, endsBlock: true), "a \\#")
        XCTAssertEqual(MarkdownEscaper.escape("a ##  ", context: .heading, endsBlock: true), "a \\##  ")
        XCTAssertEqual(MarkdownEscaper.escape("a # b", context: .heading, endsBlock: true), "a # b")
        XCTAssertEqual(MarkdownEscaper.escape("a #", context: .heading, endsBlock: false), "a #")
        XCTAssertEqual(MarkdownEscaper.escape("a #", context: .paragraph, endsBlock: true), "a #")
    }

    /// A `!` at the end of a run of text makes an image when a link node follows it.
    func testEscaperEscapesABangBeforeALinkNode() {
        XCTAssertEqual(MarkdownEscaper.escape("wow!", context: .paragraph, isFollowedByLink: true), "wow\\!")
        XCTAssertEqual(MarkdownEscaper.escape("wow!", context: .paragraph, isFollowedByLink: false), "wow!")
    }

    // MARK: - A second read must give the same text

    /// The text of a block is markdown source. Thus reading that text again must give
    /// the same text. If it does not, each write of the file changes the file again.
    func testBlockTextIsStableThroughASecondRead() {
        for source in EscapeCases.all {
            let once = paragraphText(source)
            let twice = paragraphText(once)
            XCTAssertEqual(twice, once, "the text moved on the second read of \(source.debugDescription)")
        }
    }
}
