//
//  InputReaderTests.swift
//  md
//
//  Created by Adam Wulf on 4/12/26.
//

import XCTest
import Darwin
@testable import md

private func inputReaderTestSignalHandler(_ signal: Int32) {}

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

    func testReadSourceReportsByteOrderMarkSeparately() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("md-test-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: file) }

        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(contentsOf: Data("# Heading\n".utf8))
        try data.write(to: file)

        let source = try InputReader.readSource(from: file.path)
        XCTAssertTrue(source.hasUTF8ByteOrderMark)
        XCTAssertEqual(source.content, "# Heading\n")
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

    func testWritePreservesExistingUTF8ByteOrderMark() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("md-test-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: file) }

        var original = Data([0xEF, 0xBB, 0xBF])
        original.append(contentsOf: Data("# Original\n".utf8))
        try original.write(to: file)

        try InputReader.write("# Replaced\n", to: file.path)

        var expected = Data([0xEF, 0xBB, 0xBF])
        expected.append(contentsOf: Data("# Replaced\n".utf8))
        XCTAssertEqual(try Data(contentsOf: file), expected)
    }

    func testEncodedUTF8CanIncludeByteOrderMark() {
        XCTAssertEqual(
            InputReader.encodedUTF8("# Heading", includeByteOrderMark: true),
            Data([0xEF, 0xBB, 0xBF]) + Data("# Heading".utf8)
        )
    }

    func testWritePreservesExtendedAttributes() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("md-test-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("# Original\n".utf8).write(to: file)

        let attributeName = "com.openai.md.tests"
        let attributeValue = Data("preserved".utf8)
        let setResult = file.path.withCString { path in
            attributeName.withCString { name in
                attributeValue.withUnsafeBytes { bytes in
                    setxattr(path, name, bytes.baseAddress, bytes.count, 0, 0)
                }
            }
        }
        XCTAssertEqual(setResult, 0)

        try InputReader.write("# Replaced\n", to: file.path)

        var buffer = [UInt8](repeating: 0, count: 64)
        let length = file.path.withCString { path in
            attributeName.withCString { name in
                getxattr(path, name, &buffer, buffer.count, 0, 0)
            }
        }
        XCTAssertEqual(
            String(decoding: buffer.prefix(max(0, length)), as: UTF8.self),
            "preserved"
        )
    }

    func testCommitFailureLeavesExistingFileUntouched() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("md-test-\(UUID().uuidString)")
        let file = directory.appendingPathComponent("document.md")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        defer {
            chmod(directory.path, 0o700)
            try? FileManager.default.removeItem(at: directory)
        }

        let original = Data("# Original\n".utf8)
        try original.write(to: file)
        let attributesBefore = try FileManager.default.attributesOfItem(
            atPath: file.path
        )
        var reachedCommit = false

        XCTAssertThrowsError(
            try InputReader.write(
                "# Replacement\n",
                to: file.path,
                beforeCommit: { _ in
                    reachedCommit = true
                    XCTAssertEqual(chmod(directory.path, 0o500), 0)
                }
            )
        )
        XCTAssertEqual(chmod(directory.path, 0o700), 0)

        let attributesAfter = try FileManager.default.attributesOfItem(
            atPath: file.path
        )
        XCTAssertTrue(reachedCommit)
        XCTAssertEqual(try Data(contentsOf: file), original)
        XCTAssertEqual(
            attributesAfter[.systemFileNumber] as? NSNumber,
            attributesBefore[.systemFileNumber] as? NSNumber
        )
        XCTAssertEqual(
            attributesAfter[.modificationDate] as? Date,
            attributesBefore[.modificationDate] as? Date
        )
    }

    func testWriteRestoresCompleteFileSizeSignalDisposition() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("md-test-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("# Original\n".utf8).write(to: file)

        try withCustomFileSizeSignalDisposition {
            try InputReader.write("# Replacement\n", to: file.path)
        }
    }

    func testWriteRestoresSignalDispositionAfterFileSizeFailure() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("md-test-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data(repeating: 0x41, count: 2_048).write(to: file)

        try withCustomFileSizeSignalDisposition {
            var originalLimit = rlimit()
            XCTAssertEqual(getrlimit(RLIMIT_FSIZE, &originalLimit), 0)
            var limited = originalLimit
            limited.rlim_cur = 1_024
            XCTAssertEqual(setrlimit(RLIMIT_FSIZE, &limited), 0)
            defer {
                var restored = originalLimit
                XCTAssertEqual(setrlimit(RLIMIT_FSIZE, &restored), 0)
            }

            XCTAssertThrowsError(
                try InputReader.write(
                    String(repeating: "Replacement bytes. ", count: 300),
                    to: file.path
                )
            )
        }
    }

    func testWriteRestoresSignalDispositionAfterCopyFailure() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("md-test-\(UUID().uuidString)")
        let file = directory.appendingPathComponent("document.md")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        defer {
            chmod(directory.path, 0o700)
            try? FileManager.default.removeItem(at: directory)
        }
        try Data("# Original\n".utf8).write(to: file)

        try withCustomFileSizeSignalDisposition {
            XCTAssertEqual(chmod(directory.path, 0o500), 0)
            XCTAssertThrowsError(
                try InputReader.write("# Replacement\n", to: file.path)
            )
            XCTAssertEqual(chmod(directory.path, 0o700), 0)
        }
    }

    func testWriteThroughSymbolicLinkPreservesLink() throws {
        let tmpDir = FileManager.default.temporaryDirectory
        let identifier = UUID().uuidString
        let target = tmpDir.appendingPathComponent("md-target-\(identifier).md")
        let link = tmpDir.appendingPathComponent("md-link-\(identifier).md")
        defer {
            try? FileManager.default.removeItem(at: link)
            try? FileManager.default.removeItem(at: target)
        }

        try Data("# Original\n".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(
            atPath: link.path,
            withDestinationPath: target.path
        )

        try InputReader.write("# Replaced\n", to: link.path)

        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(atPath: link.path),
            target.path
        )
        XCTAssertEqual(
            try String(contentsOf: target, encoding: .utf8),
            "# Replaced\n"
        )
    }

    private func withCustomFileSizeSignalDisposition(
        _ body: () throws -> Void
    ) throws {
        var originalDisposition = Darwin.sigaction()
        XCTAssertEqual(
            sigaction(SIGXFSZ, nil, &originalDisposition),
            0
        )
        defer {
            var restored = originalDisposition
            XCTAssertEqual(sigaction(SIGXFSZ, &restored, nil), 0)
        }

        var customDisposition = Darwin.sigaction()
        customDisposition.__sigaction_u.__sa_handler =
            inputReaderTestSignalHandler
        XCTAssertEqual(sigemptyset(&customDisposition.sa_mask), 0)
        XCTAssertEqual(
            sigaddset(&customDisposition.sa_mask, SIGUSR1),
            0
        )
        customDisposition.sa_flags = SA_RESTART
        XCTAssertEqual(
            sigaction(SIGXFSZ, &customDisposition, nil),
            0
        )

        var expectedDisposition = Darwin.sigaction()
        XCTAssertEqual(
            sigaction(SIGXFSZ, nil, &expectedDisposition),
            0
        )
        try body()

        var actualDisposition = Darwin.sigaction()
        XCTAssertEqual(
            sigaction(SIGXFSZ, nil, &actualDisposition),
            0
        )
        XCTAssertEqual(
            unsafeBitCast(
                actualDisposition.__sigaction_u.__sa_handler,
                to: UInt.self
            ),
            unsafeBitCast(
                expectedDisposition.__sigaction_u.__sa_handler,
                to: UInt.self
            )
        )
        XCTAssertEqual(
            actualDisposition.sa_mask,
            expectedDisposition.sa_mask
        )
        XCTAssertEqual(
            actualDisposition.sa_flags,
            expectedDisposition.sa_flags
        )
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
