//
//  BlockParsingFrontmatterTests.swift
//  md
//
//  Verifies that block-level commands (`md blocks`, `md toc --blocks`) skip
//  frontmatter (YAML / TOML / JSON) instead of misparsing the delimiters as
//  thematic-break + setext-heading markdown.
//

import XCTest
@testable import md
@testable import MarkdownKit

final class BlockParsingFrontmatterTests: XCTestCase {

    let parser = MarkdownParser()

    // MARK: - Document fixtures

    private let yamlDocument = """
        ---
        title: Sample
        author:
          name: Jane
        tags: [a, b]
        ---

        # Heading 1

        Para 1.

        """

    private let tomlDocument = """
        +++
        title = "Sample"
        date = 2026-04-18
        +++

        # Heading 1

        Para 1.

        """

    private let jsonDocument = """
        ;;;
        {
          "title": "Sample",
          "author": "Jane"
        }
        ;;;

        # Heading 1

        Para 1.

        """

    private let plainDocument = """
        # Heading 1

        Para 1.

        """

    // MARK: - YAML

    func testParseDocumentSkipsYAMLFrontmatter() {
        let blocks = parser.parseDocument(yamlDocument)
        XCTAssertEqual(blocks.count, 2)
        guard case .heading(let level, let text, _, _, let lineRange) = blocks[0] else {
            XCTFail("Expected first block to be a heading, got \(blocks[0])")
            return
        }
        XCTAssertEqual(level, 1)
        XCTAssertEqual(text, "Heading 1")
        // The heading is on line 8 of the original document.
        XCTAssertEqual(lineRange.lowerBound, 8)
    }

    func testParseDocumentByteRangePointsIntoOriginalForYAML() {
        let blocks = parser.parseDocument(yamlDocument)
        guard let first = blocks.first else {
            XCTFail("Expected at least one block")
            return
        }
        let utf8 = Array(yamlDocument.utf8)
        let range = first.byteRange
        let slice = Array(utf8[range.location..<min(range.location + range.length, utf8.count)])
        let text = String(decoding: slice, as: UTF8.self)
        XCTAssertTrue(text.contains("# Heading 1"), "byte range should point at the real heading, got: \(text)")
        XCTAssertFalse(text.contains("title: Sample"), "byte range should not include frontmatter")
    }

    // MARK: - TOML

    func testParseDocumentSkipsTOMLFrontmatter() {
        let blocks = parser.parseDocument(tomlDocument)
        XCTAssertEqual(blocks.count, 2)
        guard case .heading(let level, let text, _, _, let lineRange) = blocks[0] else {
            XCTFail("Expected first block to be a heading, got \(blocks[0])")
            return
        }
        XCTAssertEqual(level, 1)
        XCTAssertEqual(text, "Heading 1")
        // Heading 1 is on line 6 of the original document
        // (`+++`, two value lines, `+++`, blank line, then the heading).
        XCTAssertEqual(lineRange.lowerBound, 6)
    }

    // MARK: - JSON

    func testParseDocumentSkipsJSONFrontmatter() {
        let blocks = parser.parseDocument(jsonDocument)
        XCTAssertEqual(blocks.count, 2)
        guard case .heading(let level, let text, _, _, let lineRange) = blocks[0] else {
            XCTFail("Expected first block to be a heading, got \(blocks[0])")
            return
        }
        XCTAssertEqual(level, 1)
        XCTAssertEqual(text, "Heading 1")
        // Heading 1 is on line 8 of the original document.
        XCTAssertEqual(lineRange.lowerBound, 8)
    }

    // MARK: - No-frontmatter regression

    func testParseDocumentIsIdenticalToParseWhenNoFrontmatter() {
        let viaDocument = parser.parseDocument(plainDocument)
        let viaPlain = parser.parse(plainDocument)
        XCTAssertEqual(viaDocument.count, viaPlain.count)
        for (a, b) in zip(viaDocument, viaPlain) {
            XCTAssertEqual(a.byteRange, b.byteRange)
            XCTAssertEqual(a.lineRange, b.lineRange)
        }
        guard case .heading(_, _, _, _, let lineRange) = viaDocument[0] else {
            XCTFail("Expected heading first")
            return
        }
        XCTAssertEqual(lineRange.lowerBound, 1)
    }

    // MARK: - TOC integration

    /// Re-implements the heading-line emission of `TocCommand` against
    /// `parseDocument`, to verify the TOC produced from a frontmattered doc
    /// names the real headings (not the misparsed YAML body).
    func testTocBlocksPathSkipsFrontmatter() {
        let blocks = parser.parseDocument(yamlDocument)
        let headingLines: [String] = blocks.compactMap { block in
            if case .heading(_, let text, _, _, _) = block { return text }
            return nil
        }
        XCTAssertEqual(headingLines, ["Heading 1"], "TOC should not contain misparsed frontmatter content")
    }
}
