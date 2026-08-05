//
//  InputStreamTests.swift
//  md
//
//  Covers the standard-input and standard-output halves of InputReader, and
//  the InputOptions accessors that choose between a file and a stream.
//

import XCTest
@testable import md

final class InputStreamTests: XCTestCase {

    private var scratch: ScratchDirectory!

    override func setUpWithError() throws {
        scratch = try ScratchDirectory()
    }

    override func tearDownWithError() throws {
        scratch = nil
    }

    // MARK: - readFromStdin

    func testReadFromStdinReturnsTheWholeStream() async throws {
        let content = try await StandardStream.withStandardInput("# Piped\n\nBody.\n") {
            InputReader.readFromStdin()
        }
        XCTAssertEqual(content, "# Piped\n\nBody.\n")
    }

    func testReadFromStdinReturnsAnEmptyStringForAnEmptyStream() async throws {
        let content = try await StandardStream.withStandardInput("") {
            InputReader.readFromStdin()
        }
        XCTAssertEqual(content, "")
    }

    /// Decoding drops the mark from the text, which is why the reader carries
    /// it alongside as a flag for the writer to restore.
    func testReadSourceFromStdinReportsAByteOrderMarkWithoutKeepingItInTheText() async throws {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(contentsOf: Data("# Heading\n".utf8))

        let source = try await StandardStream.withStandardInput(data) {
            InputReader.readSourceFromStdin()
        }
        XCTAssertTrue(source.hasUTF8ByteOrderMark)
        XCTAssertEqual(source.content, "# Heading\n")
    }

    func testReadSourceFromStdinReportsNoByteOrderMarkWhenThereIsNone() async throws {
        let source = try await StandardStream.withStandardInput("# Heading\n") {
            InputReader.readSourceFromStdin()
        }
        XCTAssertFalse(source.hasUTF8ByteOrderMark)
        XCTAssertEqual(source.content, "# Heading\n")
    }

    /// The reader loops while each read fills its 64 KB buffer, so a stream that
    /// is an exact multiple of the buffer size must not be truncated.
    func testReadFromStdinReadsAStreamOfExactlyOneBufferLength() async throws {
        let text = String(repeating: "a", count: 64 * 1024)
        let content = try await StandardStream.withStandardInput(text) {
            InputReader.readFromStdin()
        }
        XCTAssertEqual(content.count, 64 * 1024)
        XCTAssertEqual(content, text)
    }

    func testReadFromStdinReadsAStreamLongerThanTheBuffer() async throws {
        let text = String(repeating: "0123456789", count: 30_000)
        let content = try await StandardStream.withStandardInput(text) {
            InputReader.readFromStdin()
        }
        XCTAssertEqual(content.count, 300_000)
        XCTAssertEqual(content, text)
    }

    func testReadFromStdinYieldsAnEmptyStringForBytesThatAreNotUTF8() async throws {
        let content = try await StandardStream.withStandardInput(Data([0xFF, 0xFE, 0x00])) {
            InputReader.readFromStdin()
        }
        XCTAssertEqual(content, "")
    }

    func testReadFromStdinPreservesMultiByteCharacters() async throws {
        let content = try await StandardStream.withStandardInput("Café 🌍 déjà\n") {
            InputReader.readFromStdin()
        }
        XCTAssertEqual(content, "Café 🌍 déjà\n")
    }

    // MARK: - writeToStdout

    func testWriteToStdoutEmitsTheContentUnchanged() async throws {
        let output = try await StandardStream.capturingStandardOutput {
            try InputReader.writeToStdout("# Heading\n", includeByteOrderMark: false)
        }
        XCTAssertEqual(output, "# Heading\n")
    }

    func testWriteToStdoutCanPrependAByteOrderMark() async throws {
        let output = try await StandardStream.capturingStandardOutputData {
            try InputReader.writeToStdout("# Heading\n", includeByteOrderMark: true)
        }
        var expected = Data([0xEF, 0xBB, 0xBF])
        expected.append(contentsOf: Data("# Heading\n".utf8))
        XCTAssertEqual(output, expected)
    }

    func testWriteToStdoutEmitsNothingForEmptyContent() async throws {
        let output = try await StandardStream.capturingStandardOutput {
            try InputReader.writeToStdout("", includeByteOrderMark: false)
        }
        XCTAssertEqual(output, "")
    }

    // MARK: - encodedUTF8

    func testEncodedUTF8OmitsTheByteOrderMarkWhenNotAsked() {
        XCTAssertEqual(
            InputReader.encodedUTF8("# Heading", includeByteOrderMark: false),
            Data("# Heading".utf8)
        )
    }

    func testEncodedUTF8OfAnEmptyStringWithoutAMarkIsEmpty() {
        XCTAssertEqual(
            InputReader.encodedUTF8("", includeByteOrderMark: false),
            Data()
        )
    }

    func testEncodedUTF8OfAnEmptyStringWithAMarkIsJustTheMark() {
        XCTAssertEqual(
            InputReader.encodedUTF8("", includeByteOrderMark: true),
            Data([0xEF, 0xBB, 0xBF])
        )
    }

    // MARK: - read / readSource from a file

    func testReadSourceReportsNoByteOrderMarkForAPlainFile() throws {
        let path = try scratch.write("# Heading\n", to: "plain.md")
        let source = try InputReader.readSource(from: path)
        XCTAssertFalse(source.hasUTF8ByteOrderMark)
        XCTAssertEqual(source.content, "# Heading\n")
    }

    func testReadSourceOfAMissingFileThrows() {
        let missing = scratch.url.appendingPathComponent("absent.md").path
        XCTAssertThrowsError(try InputReader.readSource(from: missing))
    }

    func testReadOfADirectoryThrows() {
        XCTAssertThrowsError(try InputReader.read(from: scratch.url.path))
    }

    func testReadOfAnEmptyFileReturnsAnEmptyString() throws {
        let path = try scratch.write("", to: "empty.md")
        XCTAssertEqual(try InputReader.read(from: path), "")
    }

    // MARK: - InputOptions

    func testReadContentFromAFile() throws {
        let path = try scratch.write("# From file\n", to: "document.md")
        var options = InputOptions()
        options.file = path
        options.stdin = false
        XCTAssertEqual(try options.readContent(), "# From file\n")
    }

    func testReadSourceFromAFileReportsItsByteOrderMark() throws {
        let url = scratch.url.appendingPathComponent("bom.md")
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(contentsOf: Data("# Heading\n".utf8))
        try data.write(to: url)

        var options = InputOptions()
        options.file = url.path
        options.stdin = false
        let source = try options.readSource()
        XCTAssertTrue(source.hasUTF8ByteOrderMark)
        XCTAssertEqual(source.content, "# Heading\n")
    }

    func testReadContentFromStandardInput() async throws {
        var options = InputOptions()
        options.file = nil
        options.stdin = true
        let content = try await StandardStream.withStandardInput("# From stdin\n") {
            try options.readContent()
        }
        XCTAssertEqual(content, "# From stdin\n")
    }

    func testReadContentFromAMissingFileThrows() {
        var options = InputOptions()
        options.file = scratch.url.appendingPathComponent("absent.md").path
        options.stdin = false
        XCTAssertThrowsError(try options.readContent())
    }

    /// A file wins over the stream whenever one is set, which is why validate
    /// refuses to accept both at once.
    func testAFileIsPreferredOverStandardInputWhenBothAreSet() async throws {
        let path = try scratch.write("# From file\n", to: "document.md")
        var options = InputOptions()
        options.file = path
        options.stdin = true
        let content = try await StandardStream.withStandardInput("# From stdin\n") {
            try options.readContent()
        }
        XCTAssertEqual(content, "# From file\n")
    }
}
