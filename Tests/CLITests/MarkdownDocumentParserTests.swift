//
//  MarkdownDocumentParserTests.swift
//  md
//
//  parseDocument strips leading frontmatter before block parsing and then
//  shifts every block back into the coordinates of the original document.
//  These tests check the shift for each block case and each frontmatter format.
//

import XCTest
@testable import md
@testable import MarkdownKit

final class MarkdownDocumentParserTests: XCTestCase {

    let parser = MarkdownParser()

    /// Slices `document` with each block's byte range and returns the text.
    private func sources(
        of blocks: [MarkdownBlock],
        in document: String
    ) -> [String] {
        let utf8 = Array(document.utf8)
        return blocks.map { block in
            let range = block.byteRange
            let upper = min(range.location + range.length, utf8.count)
            guard range.location <= upper else { return "<invalid range>" }
            return String(decoding: utf8[range.location..<upper], as: UTF8.self)
        }
    }

    private func charSources(
        of blocks: [MarkdownBlock],
        in document: String
    ) -> [String] {
        let nsString = document as NSString
        return blocks.map { nsString.substring(with: $0.charRange) }
    }

    // MARK: - Every block case is shifted back into the original document

    private let allBlockKinds = """
        # Heading

        A paragraph.

        ```swift
        let x = 1
        ```

        - one
        - two

        > quoted

        ---

        | A | B |
        | --- | --- |
        | 1 | 2 |

        """

    /// cmark ends a list and a thematic break on the blank line that follows
    /// them, so those two ranges take in the trailing newline as well.
    private let allBlockKindSources = [
        "# Heading",
        "A paragraph.",
        "```swift\nlet x = 1\n```",
        "- one\n- two\n",
        "> quoted",
        "---\n",
        "| A | B |\n| --- | --- |\n| 1 | 2 |"
    ]

    func testEveryBlockKindKeepsItsByteRangeAfterFrontmatterIsStripped() {
        let document = "---\ntitle: A\n---\n\n" + allBlockKinds
        let blocks = parser.parseDocument(document)
        XCTAssertEqual(sources(of: blocks, in: document), allBlockKindSources)
    }

    func testEveryBlockKindKeepsItsCharacterRangeAfterFrontmatterIsStripped() {
        let document = "---\ntitle: A\n---\n\n" + allBlockKinds
        let blocks = parser.parseDocument(document)
        XCTAssertEqual(charSources(of: blocks, in: document), allBlockKindSources)
    }

    func testEveryBlockKindKeepsItsLineRangeAfterFrontmatterIsStripped() {
        let document = "---\ntitle: A\n---\n\n" + allBlockKinds
        let blocks = parser.parseDocument(document)
        XCTAssertEqual(
            blocks.map(\.lineRange),
            [5...5, 7...7, 9...11, 13...15, 16...16, 18...19, 20...22]
        )
    }

    func testEveryBlockKindKeepsItsPayloadAfterTheShift() {
        let document = "---\ntitle: A\n---\n\n" + allBlockKinds
        let blocks = parser.parseDocument(document)
        XCTAssertEqual(blocks.count, 7)

        guard case .heading(let level, let headingText, _, _, _) = blocks[0],
              case .paragraph(let paragraphText, _, _, _) = blocks[1],
              case .codeBlock(let language, let code, _, _, _) = blocks[2],
              case .list(let items, let ordered, _, _, _) = blocks[3],
              case .blockquote(let quote, _, _, _) = blocks[4],
              case .thematicBreak = blocks[5],
              case .table(let rows, _, _, _) = blocks[6] else {
            return XCTFail("Unexpected block kinds: \(blocks)")
        }

        XCTAssertEqual(level, 1)
        XCTAssertEqual(headingText, "Heading")
        XCTAssertEqual(paragraphText, "A paragraph.")
        XCTAssertEqual(language, "swift")
        XCTAssertEqual(code, "let x = 1\n")
        XCTAssertEqual(items.map(\.text), ["one", "two"])
        XCTAssertFalse(ordered)
        XCTAssertEqual(quote, "quoted")
        XCTAssertEqual(rows, [["A", "B"], ["1", "2"]])
    }

    // MARK: - Each frontmatter format

    func testTOMLFrontmatterIsStrippedAndOffsetsRestored() {
        let document = "+++\ntitle = \"A\"\n+++\n\n# Heading\n"
        let blocks = parser.parseDocument(document)
        XCTAssertEqual(sources(of: blocks, in: document), ["# Heading"])
        XCTAssertEqual(blocks.map(\.lineRange), [5...5])
    }

    func testJSONFrontmatterIsStrippedAndOffsetsRestored() {
        let document = ";;;\n{\"title\": \"A\"}\n;;;\n\n# Heading\n"
        let blocks = parser.parseDocument(document)
        XCTAssertEqual(sources(of: blocks, in: document), ["# Heading"])
        XCTAssertEqual(blocks.map(\.lineRange), [5...5])
    }

    func testEmptyFrontmatterIsStillStripped() {
        let document = "---\n---\n\n# Heading\n"
        let blocks = parser.parseDocument(document)
        XCTAssertEqual(sources(of: blocks, in: document), ["# Heading"])
        XCTAssertEqual(blocks.map(\.lineRange), [4...4])
    }

    func testMultiLineFrontmatterShiftsByItsFullHeight() {
        let document = """
            ---
            title: A
            author:
              name: Jane
            tags:
              - one
              - two
            ---

            # Heading
            """
        let blocks = parser.parseDocument(document)
        XCTAssertEqual(sources(of: blocks, in: document), ["# Heading"])
        XCTAssertEqual(blocks.map(\.lineRange), [10...10])
    }

    // MARK: - Documents without frontmatter are untouched

    func testADocumentWithoutFrontmatterIsParsedWithNoShift() {
        let document = "# Heading\n\nBody.\n"
        let viaDocument = parser.parseDocument(document)
        let viaParse = parser.parse(document)
        XCTAssertEqual(viaDocument.map(\.byteRange), viaParse.map(\.byteRange))
        XCTAssertEqual(viaDocument.map(\.charRange), viaParse.map(\.charRange))
        XCTAssertEqual(viaDocument.map(\.lineRange), viaParse.map(\.lineRange))
    }

    func testAnEmptyDocumentHasNoBlocks() {
        XCTAssertEqual(parser.parseDocument("").count, 0)
    }

    func testADocumentThatIsOnlyFrontmatterHasNoBlocks() {
        XCTAssertEqual(parser.parseDocument("---\ntitle: A\n---\n").count, 0)
    }

    func testADocumentThatIsOnlyFrontmatterWithoutATrailingNewlineHasNoBlocks() {
        XCTAssertEqual(parser.parseDocument("---\ntitle: A\n---").count, 0)
    }

    // MARK: - Line endings

    func testCarriageReturnLineFeedFrontmatterShiftsByOneLinePerPair() {
        let document = "---\r\ntitle: A\r\n---\r\n\r\n# Heading\r\n"
        let blocks = parser.parseDocument(document)
        XCTAssertEqual(sources(of: blocks, in: document), ["# Heading"])
        XCTAssertEqual(blocks.map(\.lineRange), [5...5])
    }

    func testLoneCarriageReturnFrontmatterShiftsByOneLinePerReturn() {
        let document = "---\rtitle: A\r---\r\r# Heading\r"
        let blocks = parser.parseDocument(document)
        XCTAssertEqual(sources(of: blocks, in: document), ["# Heading"])
        XCTAssertEqual(blocks.map(\.lineRange), [5...5])
    }

    // MARK: - Multi-byte frontmatter

    /// The byte offset and the UTF-16 offset are computed separately, so a
    /// multi-byte value in the frontmatter must shift them by different amounts.
    func testMultiByteFrontmatterShiftsByteAndCharacterOffsetsIndependently() {
        let document = "---\ntitle: Café 🌍\n---\n\n# Heading\n"
        let blocks = parser.parseDocument(document)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(sources(of: blocks, in: document), ["# Heading"])
        XCTAssertEqual(charSources(of: blocks, in: document), ["# Heading"])
        XCTAssertNotEqual(
            blocks[0].byteRange.location,
            blocks[0].charRange.location,
            "a 4-byte emoji in the frontmatter should push the byte offset "
                + "further than the UTF-16 offset"
        )
    }

    func testMultiByteBodyAfterFrontmatterKeepsBothOffsetsCorrect() {
        let document = "---\ntitle: A\n---\n\n# Héllo 🌍\n\nCafé déjà\n"
        let blocks = parser.parseDocument(document)
        XCTAssertEqual(
            sources(of: blocks, in: document),
            ["# Héllo 🌍", "Café déjà"]
        )
        XCTAssertEqual(
            charSources(of: blocks, in: document),
            ["# Héllo 🌍", "Café déjà"]
        )
    }
}
