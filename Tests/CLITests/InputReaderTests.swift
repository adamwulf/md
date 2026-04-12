//
//  InputReaderTests.swift
//  md
//
//  Created by Adam Wulf on 4/12/26.
//

import XCTest
@testable import md

final class InputReaderTests: XCTestCase {

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

    // MARK: - write(_:to:)

    func testWriteToFile() throws {
        let tmpDir = FileManager.default.temporaryDirectory
        let file = tmpDir.appendingPathComponent("md-test-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: file) }

        try InputReader.write("# Written\n", to: file.path)
        let content = try String(contentsOf: file, encoding: .utf8)
        XCTAssertEqual(content, "# Written\n")
    }

    func testWriteOverwritesExisting() throws {
        let tmpDir = FileManager.default.temporaryDirectory
        let file = tmpDir.appendingPathComponent("md-test-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: file) }

        try "original".write(to: file, atomically: true, encoding: .utf8)
        try InputReader.write("replaced", to: file.path)
        let content = try String(contentsOf: file, encoding: .utf8)
        XCTAssertEqual(content, "replaced")
    }

    // MARK: - InputOptions validation

    func testInputOptionsRequiresFileOrStdin() throws {
        var opts = InputOptions()
        opts.file = nil
        opts.stdin = false
        XCTAssertThrowsError(try opts.validate())
    }

    func testInputOptionsRejectsFileAndStdin() throws {
        var opts = InputOptions()
        opts.file = "/some/file.md"
        opts.stdin = true
        XCTAssertThrowsError(try opts.validate())
    }

    func testInputOptionsAcceptsFile() throws {
        var opts = InputOptions()
        opts.file = "/some/file.md"
        opts.stdin = false
        XCTAssertNoThrow(try opts.validate())
    }

    func testInputOptionsAcceptsStdin() throws {
        var opts = InputOptions()
        opts.file = nil
        opts.stdin = true
        XCTAssertNoThrow(try opts.validate())
    }
}
