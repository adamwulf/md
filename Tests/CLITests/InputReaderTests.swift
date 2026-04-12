//
//  InputReaderTests.swift
//  md
//
//  Created by Adam Wulf on 4/12/26.
//

import XCTest
@testable import md

final class InputReaderTests: XCTestCase {

    // MARK: - parsePassthrough

    func testParsePassthroughEmpty() {
        let result = InputReader.parsePassthrough([])
        XCTAssertEqual(result.indices, [])
        XCTAssertNil(result.file)
    }

    func testParsePassthroughFileOnly() {
        let result = InputReader.parsePassthrough(["README.md"])
        XCTAssertEqual(result.indices, [])
        XCTAssertEqual(result.file, "README.md")
    }

    func testParsePassthroughSingleIndexAndFile() {
        let result = InputReader.parsePassthrough(["5", "README.md"])
        XCTAssertEqual(result.indices, [5])
        XCTAssertEqual(result.file, "README.md")
    }

    func testParsePassthroughRangeAndFile() {
        let result = InputReader.parsePassthrough(["1", "10", "README.md"])
        XCTAssertEqual(result.indices, [1, 10])
        XCTAssertEqual(result.file, "README.md")
    }

    func testParsePassthroughSingleIndexNoFile() {
        let result = InputReader.parsePassthrough(["5"])
        XCTAssertEqual(result.indices, [5])
        XCTAssertNil(result.file)
    }

    func testParsePassthroughRangeNoFile() {
        let result = InputReader.parsePassthrough(["1", "10"])
        XCTAssertEqual(result.indices, [1, 10])
        XCTAssertNil(result.file)
    }

    // MARK: - read(from:) with file

    func testReadFromFile() throws {
        let tmpDir = FileManager.default.temporaryDirectory
        let file = tmpDir.appendingPathComponent("md-test-\(UUID().uuidString).md")
        try "# Test\n\nHello".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        let content = try InputReader.read(from: file.path)
        XCTAssertEqual(content, "# Test\n\nHello")
    }

    func testReadFromNonexistentFile() {
        XCTAssertThrowsError(try InputReader.read(from: "/tmp/nonexistent-\(UUID().uuidString).md"))
    }
}
