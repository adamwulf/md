//
//  CommandTests.swift
//  md
//
//  Created by Adam Wulf on 4/12/26.
//

import XCTest
@testable import md
@testable import MarkdownKit

final class CommandTests: XCTestCase {

    let parser = MarkdownParser()

    let sampleMarkdown = """
        # Title

        First paragraph.

        ## Section

        Second paragraph.
        """

    // MARK: - Remove Logic

    func testRemoveSingleBlock() {
        let blocks = parser.parse(sampleMarkdown)
        // Remove block 1 (the heading)
        let remaining = blocks.enumerated().filter { $0.offset + 1 != 1 }.map { $0.element }
        let result = BlockFormatter.format(remaining)
        XCTAssertFalse(result.contains("# Title"))
        XCTAssertTrue(result.contains("First paragraph."))
    }

    func testRemoveBlockRange() {
        let blocks = parser.parse(sampleMarkdown)
        // Remove blocks 1-2 (heading + first paragraph)
        let remaining = blocks.enumerated().filter { blockNum in
            let num = blockNum.offset + 1
            return num < 1 || num > 2
        }.map { $0.element }
        let result = BlockFormatter.format(remaining)
        XCTAssertFalse(result.contains("# Title"))
        XCTAssertFalse(result.contains("First paragraph."))
        XCTAssertTrue(result.contains("## Section"))
    }

    func testRemoveLastBlock() {
        let blocks = parser.parse(sampleMarkdown)
        let lastIndex = blocks.count
        let remaining = blocks.enumerated().filter { $0.offset + 1 != lastIndex }.map { $0.element }
        let result = BlockFormatter.format(remaining)
        XCTAssertTrue(result.contains("# Title"))
        XCTAssertFalse(result.contains("Second paragraph."))
    }

    func testRemoveAllBlocks() {
        let blocks = parser.parse(sampleMarkdown)
        let remaining = blocks.enumerated().filter { blockNum in
            let num = blockNum.offset + 1
            return num < 1 || num > blocks.count
        }.map { $0.element }
        let result = BlockFormatter.format(remaining)
        XCTAssertEqual(result, "")
    }

    // MARK: - Replace Logic

    func testReplaceSingleBlock() {
        let blocks = parser.parse(sampleMarkdown)
        let newBlocks = parser.parse("# New Title")

        var result = ""
        for (i, block) in blocks.enumerated() {
            let blockNum = i + 1
            if blockNum == 1 {
                if !result.isEmpty { result += "\n" }
                result += BlockFormatter.format(newBlocks)
            } else {
                if !result.isEmpty { result += "\n" }
                result += BlockFormatter.format(block)
            }
        }

        XCTAssertTrue(result.contains("# New Title"))
        XCTAssertFalse(result.contains("# Title\n"))
        XCTAssertTrue(result.contains("First paragraph."))
    }

    func testReplaceBlockRange() {
        let blocks = parser.parse(sampleMarkdown)
        let newBlocks = parser.parse("Replacement.")
        let start = 1
        let end = 2

        var result = ""
        for (i, block) in blocks.enumerated() {
            let blockNum = i + 1
            if blockNum == start {
                if !result.isEmpty { result += "\n" }
                result += BlockFormatter.format(newBlocks)
            } else if blockNum > start && blockNum <= end {
                continue
            } else {
                if !result.isEmpty { result += "\n" }
                result += BlockFormatter.format(block)
            }
        }

        XCTAssertTrue(result.contains("Replacement."))
        XCTAssertFalse(result.contains("# Title"))
        XCTAssertFalse(result.contains("First paragraph."))
        XCTAssertTrue(result.contains("## Section"))
    }

    func testReplaceWithMultipleBlocks() {
        let blocks = parser.parse(sampleMarkdown)
        let newBlocks = parser.parse("# Replaced\n\nNew paragraph.")

        var result = ""
        for (i, block) in blocks.enumerated() {
            let blockNum = i + 1
            if blockNum == 3 {
                if !result.isEmpty { result += "\n" }
                result += BlockFormatter.format(newBlocks)
            } else {
                if !result.isEmpty { result += "\n" }
                result += BlockFormatter.format(block)
            }
        }

        XCTAssertTrue(result.contains("# Title"))
        XCTAssertTrue(result.contains("# Replaced"))
        XCTAssertTrue(result.contains("New paragraph."))
        XCTAssertFalse(result.contains("## Section"))
    }

    // MARK: - Insert After Logic

    func testInsertAfterFirstBlock() {
        let blocks = parser.parse(sampleMarkdown)
        let newBlocks = parser.parse("Inserted content.")
        let formattedNew = BlockFormatter.format(newBlocks)
        let targetIndex = 1

        var result = ""
        for (i, block) in blocks.enumerated() {
            if i > 0 { result += "\n" }
            result += BlockFormatter.format(block)
            if i + 1 == targetIndex {
                result += "\n" + formattedNew
            }
        }

        let titleRange = result.range(of: "# Title")!
        let insertedRange = result.range(of: "Inserted content.")!
        let paraRange = result.range(of: "First paragraph.")!
        XCTAssertTrue(titleRange.lowerBound < insertedRange.lowerBound)
        XCTAssertTrue(insertedRange.lowerBound < paraRange.lowerBound)
    }

    func testInsertAfterLastBlock() {
        let blocks = parser.parse(sampleMarkdown)
        let newBlocks = parser.parse("End content.")
        let formattedNew = BlockFormatter.format(newBlocks)
        let targetIndex = blocks.count

        var result = ""
        for (i, block) in blocks.enumerated() {
            if i > 0 { result += "\n" }
            result += BlockFormatter.format(block)
            if i + 1 == targetIndex {
                result += "\n" + formattedNew
            }
        }

        XCTAssertTrue(result.hasSuffix("End content.\n"))
    }

    // MARK: - Insert Before Logic

    func testInsertBeforeFirstBlock() {
        let blocks = parser.parse(sampleMarkdown)
        let newBlocks = parser.parse("Preamble.")
        let formattedNew = BlockFormatter.format(newBlocks)
        let targetIndex = 1

        var result = ""
        for (i, block) in blocks.enumerated() {
            if i + 1 == targetIndex {
                if i > 0 { result += "\n" }
                result += formattedNew + "\n"
                result += BlockFormatter.format(block)
            } else {
                if i > 0 { result += "\n" }
                result += BlockFormatter.format(block)
            }
        }

        XCTAssertTrue(result.hasPrefix("Preamble.\n"))
        let preambleRange = result.range(of: "Preamble.")!
        let titleRange = result.range(of: "# Title")!
        XCTAssertTrue(preambleRange.lowerBound < titleRange.lowerBound)
    }

    func testInsertBeforeLastBlock() {
        let blocks = parser.parse(sampleMarkdown)
        let newBlocks = parser.parse("Before last.")
        let formattedNew = BlockFormatter.format(newBlocks)
        let targetIndex = blocks.count

        var result = ""
        for (i, block) in blocks.enumerated() {
            if i + 1 == targetIndex {
                if i > 0 { result += "\n" }
                result += formattedNew + "\n"
                result += BlockFormatter.format(block)
            } else {
                if i > 0 { result += "\n" }
                result += BlockFormatter.format(block)
            }
        }

        let beforeRange = result.range(of: "Before last.")!
        let lastRange = result.range(of: "Second paragraph.")!
        XCTAssertTrue(beforeRange.lowerBound < lastRange.lowerBound)
    }

    // MARK: - In-Place Write

    func testInPlaceWrite() throws {
        let tmpDir = FileManager.default.temporaryDirectory
        let tmpFile = tmpDir.appendingPathComponent("test_inplace_\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        try "# Hello\n\nWorld.\n".write(to: tmpFile, atomically: true, encoding: .utf8)

        let content = try InputReader.read(from: tmpFile.path)
        let blocks = parser.parse(content)
        // Remove block 2 (the paragraph)
        let remaining = blocks.enumerated().filter { $0.offset + 1 != 2 }.map { $0.element }
        let result = BlockFormatter.format(remaining)
        try InputReader.write(result, to: tmpFile.path)

        let written = try String(contentsOf: tmpFile, encoding: .utf8)
        XCTAssertEqual(written, "# Hello\n")
        XCTAssertFalse(written.contains("World."))
    }

    func testInPlaceWritePreservesContent() throws {
        let tmpDir = FileManager.default.temporaryDirectory
        let tmpFile = tmpDir.appendingPathComponent("test_inplace_\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let original = "# Title\n\nParagraph.\n"
        try original.write(to: tmpFile, atomically: true, encoding: .utf8)

        let content = try InputReader.read(from: tmpFile.path)
        let blocks = parser.parse(content)
        let result = BlockFormatter.format(blocks)
        try InputReader.write(result, to: tmpFile.path)

        let written = try String(contentsOf: tmpFile, encoding: .utf8)
        XCTAssertEqual(written, original)
    }

    // MARK: - Format Logic

    func testFormatNormalizesMarkdown() {
        let input = "# Title\n\nSome text.\n\n- item1\n- item2"
        let blocks = parser.parse(input)
        let result = BlockFormatter.format(blocks)
        XCTAssertTrue(result.contains("# Title\n"))
        XCTAssertTrue(result.contains("Some text.\n"))
        XCTAssertTrue(result.contains("- item1\n- item2\n"))
    }

    // MARK: - Blocks Logic

    func testBlockCount() {
        let blocks = parser.parse(sampleMarkdown)
        XCTAssertEqual(blocks.count, 4)
    }

    func testBlockIndexRange() {
        let blocks = parser.parse(sampleMarkdown)
        // Blocks 2-3 should be "First paragraph." and "## Section"
        let slice = Array(blocks[1...2])
        XCTAssertEqual(slice.count, 2)
        if case .paragraph(let text, _, _, _) = slice[0] {
            XCTAssertEqual(text, "First paragraph.")
        } else {
            XCTFail("Expected paragraph at index 2")
        }
        if case .heading(let level, let text, _, _, _) = slice[1] {
            XCTAssertEqual(level, 2)
            XCTAssertEqual(text, "Section")
        } else {
            XCTFail("Expected heading at index 3")
        }
    }

    // MARK: - Lines Logic

    func testLineCount() {
        let lines = sampleMarkdown.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 7)
    }

    func testLineRange() {
        let lines = sampleMarkdown.components(separatedBy: "\n")
        // Lines 1-3 should be "# Title", "", "First paragraph."
        let slice = Array(lines[0...2])
        XCTAssertEqual(slice[0], "# Title")
        XCTAssertEqual(slice[1], "")
        XCTAssertEqual(slice[2], "First paragraph.")
    }

    // MARK: - Toc Logic

    func testTocFindsHeadings() {
        let blocks = parser.parse(sampleMarkdown)
        let headings = blocks.compactMap { block -> (Int, String, ClosedRange<Int>)? in
            if case .heading(let level, let text, _, _, let lineRange) = block {
                return (level, text, lineRange)
            }
            return nil
        }
        XCTAssertEqual(headings.count, 2)
        XCTAssertEqual(headings[0].0, 1) // level
        XCTAssertEqual(headings[0].1, "Title")
        XCTAssertEqual(headings[1].0, 2) // level
        XCTAssertEqual(headings[1].1, "Section")
    }

    func testTocHeadingIndent() {
        // Level 1 = no indent, level 2 = 2 spaces, level 3 = 4 spaces
        let indent1 = String(repeating: "  ", count: 1 - 1)
        let indent2 = String(repeating: "  ", count: 2 - 1)
        let indent3 = String(repeating: "  ", count: 3 - 1)
        XCTAssertEqual(indent1, "")
        XCTAssertEqual(indent2, "  ")
        XCTAssertEqual(indent3, "    ")
    }
}
