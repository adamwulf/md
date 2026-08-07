//
//  LinkReferenceDefinitionParsingTests.swift
//  md
//
//  Created by Claude on 8/7/26.
//

import XCTest
@testable import MarkdownKit

/// Defects 7 and 27, at the parser level. cmark consumes a link reference
/// definition into the document's reference map and leaves no node in the
/// tree, and it resolves each link that used one to hold the URL inline. The
/// parser reads the definitions back out of the source and keeps every
/// reference-style link in its authored spelling.
final class LinkReferenceDefinitionParsingTests: XCTestCase {

    let parser = MarkdownParser()

    /// A definition that no link uses is still text the author wrote, so it
    /// comes back as a block of its own, at its place in the source.
    func testParseKeepsAnUnusedDefinitionAsABlock() {
        let blocks = parser.parse("Just a paragraph.\n\n[unused]: https://example.org\n")
        XCTAssertEqual(blocks.count, 2)
        if case .linkReferenceDefinition(let text, _, let byteRange, let lineRange) = blocks[1] {
            XCTAssertEqual(text, "[unused]: https://example.org")
            XCTAssertEqual(lineRange, 3...3)
            XCTAssertEqual(byteRange, NSRange(location: 19, length: 29))
        } else {
            XCTFail("Expected a link reference definition block")
        }
    }

    /// A link that used a definition keeps the author's reference spelling in
    /// the paragraph text, not the resolved `[ref](url)` form.
    func testParseKeepsAReferenceStyleLinkAsWritten() {
        let blocks = parser.parse("paragraph [ref] here\n\n[ref]: url\n")
        XCTAssertEqual(blocks.count, 2)
        if case .paragraph(let text, _, _, _) = blocks[0] {
            XCTAssertEqual(text, "paragraph [ref] here")
        } else {
            XCTFail("Expected a paragraph block")
        }
    }

    /// A full reference names its label second and a collapsed one repeats
    /// its own text. Both keep their authored spelling.
    func testParseKeepsFullAndCollapsedReferencesAsWritten() {
        let blocks = parser.parse("See [the docs][ref] and [ref][] here.\n\n[ref]: /url\n")
        XCTAssertEqual(blocks.count, 2)
        if case .paragraph(let text, _, _, _) = blocks[0] {
            XCTAssertEqual(text, "See [the docs][ref] and [ref][] here.")
        } else {
            XCTFail("Expected a paragraph block")
        }
    }

    /// A bracket that resolves against no definition is ordinary text and
    /// keeps its backslash, so it cannot become a link on the next parse.
    func testParseStillEscapesABracketThatResolvesNothing() {
        let blocks = parser.parse("paragraph [missing] here\n\n[ref]: url\n")
        XCTAssertEqual(blocks.count, 2)
        if case .paragraph(let text, _, _, _) = blocks[0] {
            XCTAssertEqual(text, "paragraph \\[missing] here")
        } else {
            XCTFail("Expected a paragraph block")
        }
    }

    /// A definition that was an item's only content goes back inside that
    /// item, not after the list.
    func testParseKeepsADefinitionInsideItsOwnItem() {
        let blocks = parser.parse("# Title\n\n- [ref]: /url\n")
        XCTAssertEqual(blocks.count, 2)
        if case .list(let items, _, _, _, _) = blocks[1] {
            XCTAssertEqual(items.map(\.text), ["[ref]: /url"])
        } else {
            XCTFail("Expected a list block")
        }
    }

    /// A definition below an item's text stays that item's later paragraph,
    /// at the line the author wrote it on.
    func testParseKeepsADefinitionBelowItemText() {
        let blocks = parser.parse("- Some text\n\n  [ref]: /url\n")
        XCTAssertEqual(blocks.count, 1)
        if case .list(let items, _, _, _, _) = blocks[0] {
            XCTAssertEqual(items.map(\.text), ["Some text\n\n[ref]: /url"])
        } else {
            XCTFail("Expected a list block")
        }
    }
}
