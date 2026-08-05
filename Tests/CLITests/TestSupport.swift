//
//  TestSupport.swift
//  md
//
//  Shared helpers for the CLI test target. Commands write their results with
//  `print` and `FileHandle.standardOutput`, so tests that assert on exact
//  output must capture the process descriptors themselves.
//

import Foundation
import XCTest

enum StandardStream {

    struct CapturedCommandRun {
        let standardOutput: String
        let standardError: String
        let error: Error?
    }

    /// Runs `body` with `STDOUT_FILENO` pointed at a scratch file and returns
    /// everything the body wrote. A file is used instead of a pipe because a
    /// pipe fills after 64 KB and would deadlock a body that writes more.
    ///
    /// Both `print` (buffered stdio) and `FileHandle.standardOutput` (raw
    /// descriptor) land in the same file, so their relative order is preserved
    /// only after the stdio buffer is flushed — which this helper does before
    /// restoring the original descriptor.
    static func capturingStandardOutput(
        _ body: () async throws -> Void
    ) async throws -> String {
        let data = try await capturingStandardOutputData(body)
        guard let text = String(data: data, encoding: .utf8) else {
            throw TestSupportError.capturedOutputIsNotUTF8
        }
        return text
    }

    /// The `Data` form of `capturingStandardOutput`. Reading the capture back
    /// as a `String` through Foundation drops a leading byte order mark, so
    /// tests that assert on the mark itself must compare bytes.
    static func capturingStandardOutputData(
        _ body: () async throws -> Void
    ) async throws -> Data {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("md-stdout-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw TestSupportError.cannotCreateScratchFile(url.path)
        }
        defer { try? FileManager.default.removeItem(at: url) }

        fflush(stdout)
        let savedDescriptor = dup(STDOUT_FILENO)
        guard savedDescriptor >= 0 else {
            throw TestSupportError.cannotDuplicateDescriptor
        }
        let redirectDescriptor = open(url.path, O_WRONLY | O_TRUNC)
        guard redirectDescriptor >= 0 else {
            close(savedDescriptor)
            throw TestSupportError.cannotCreateScratchFile(url.path)
        }
        dup2(redirectDescriptor, STDOUT_FILENO)
        close(redirectDescriptor)

        var restored = false
        func restore() {
            guard !restored else { return }
            restored = true
            fflush(stdout)
            dup2(savedDescriptor, STDOUT_FILENO)
            close(savedDescriptor)
        }
        defer { restore() }

        try await body()
        restore()

        return try Data(contentsOf: url)
    }

    /// Captures both output streams and the error thrown by a command. Unlike
    /// `capturingStandardOutput`, the command error is returned rather than
    /// rethrown so tests can assert on bytes written before a final exit code.
    static func capturingCommandRun(
        _ body: () async throws -> Void
    ) async throws -> CapturedCommandRun {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("md-stdout-\(UUID().uuidString)")
        let errorURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("md-stderr-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: outputURL.path, contents: nil),
              FileManager.default.createFile(atPath: errorURL.path, contents: nil) else {
            throw TestSupportError.cannotCreateScratchFile(outputURL.path)
        }
        defer {
            try? FileManager.default.removeItem(at: outputURL)
            try? FileManager.default.removeItem(at: errorURL)
        }

        fflush(stdout)
        fflush(stderr)
        let savedOutput = dup(STDOUT_FILENO)
        let savedError = dup(STDERR_FILENO)
        guard savedOutput >= 0, savedError >= 0 else {
            if savedOutput >= 0 { close(savedOutput) }
            if savedError >= 0 { close(savedError) }
            throw TestSupportError.cannotDuplicateDescriptor
        }

        let redirectedOutput = open(outputURL.path, O_WRONLY | O_TRUNC)
        let redirectedError = open(errorURL.path, O_WRONLY | O_TRUNC)
        guard redirectedOutput >= 0, redirectedError >= 0 else {
            close(savedOutput)
            close(savedError)
            if redirectedOutput >= 0 { close(redirectedOutput) }
            if redirectedError >= 0 { close(redirectedError) }
            throw TestSupportError.cannotCreateScratchFile(outputURL.path)
        }

        dup2(redirectedOutput, STDOUT_FILENO)
        dup2(redirectedError, STDERR_FILENO)
        close(redirectedOutput)
        close(redirectedError)

        var commandError: Error?
        do {
            try await body()
        } catch {
            commandError = error
        }

        fflush(stdout)
        fflush(stderr)
        dup2(savedOutput, STDOUT_FILENO)
        dup2(savedError, STDERR_FILENO)
        close(savedOutput)
        close(savedError)

        let outputData = try Data(contentsOf: outputURL)
        let errorData = try Data(contentsOf: errorURL)
        guard let output = String(data: outputData, encoding: .utf8),
              let errorOutput = String(data: errorData, encoding: .utf8) else {
            throw TestSupportError.capturedOutputIsNotUTF8
        }
        return CapturedCommandRun(
            standardOutput: output,
            standardError: errorOutput,
            error: commandError
        )
    }

    /// Runs `body` with `stdin` re-associated to a scratch file holding `text`,
    /// then puts the real descriptor back. `freopen` is used rather than a bare
    /// `dup2` so the C `FILE *` that `InputReader.readSourceFromStdin` reads
    /// through drops any buffered bytes and end-of-file flag from an earlier
    /// test.
    static func withStandardInput<T>(
        _ data: Data,
        _ body: () async throws -> T
    ) async throws -> T {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("md-stdin-\(UUID().uuidString)")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let savedDescriptor = dup(STDIN_FILENO)
        guard savedDescriptor >= 0 else {
            throw TestSupportError.cannotDuplicateDescriptor
        }
        defer {
            dup2(savedDescriptor, STDIN_FILENO)
            close(savedDescriptor)
            clearerr(stdin)
        }

        guard freopen(url.path, "r", stdin) != nil else {
            throw TestSupportError.cannotCreateScratchFile(url.path)
        }
        return try await body()
    }

    static func withStandardInput<T>(
        _ text: String,
        _ body: () async throws -> T
    ) async throws -> T {
        try await withStandardInput(Data(text.utf8), body)
    }
}

enum TestSupportError: Error, Equatable {
    case cannotCreateScratchFile(String)
    case cannotDuplicateDescriptor
    case capturedOutputIsNotUTF8
}

/// Asserts that `body` throws an error whose description is exactly
/// `expectedMessage`. `ValidationError` from ArgumentParser describes itself as
/// its message, so this pins the text the user actually sees.
func XCTAssertThrowsErrorMessage(
    _ expectedMessage: String,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ body: () async throws -> Void
) async {
    do {
        try await body()
        XCTFail(
            "Expected an error described as \"\(expectedMessage)\", but none was thrown",
            file: file,
            line: line
        )
    } catch {
        XCTAssertEqual("\(error)", expectedMessage, file: file, line: line)
    }
}

/// A directory under the system temporary directory that removes itself when
/// the owning test case tears down.
final class ScratchDirectory {

    let url: URL

    /// The path is resolved once the directory exists. On macOS the temporary
    /// directory is reached through a symlink (/var to /private/var) and
    /// FileManager's directory enumerator reports the resolved form, so tests
    /// that compare emitted paths need the resolved form to start with.
    /// `realpath` is used rather than `resolvingSymlinksInPath()`, which puts
    /// the /private prefix straight back to /var.
    init() throws {
        let created = FileManager.default.temporaryDirectory
            .appendingPathComponent("md-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: created,
            withIntermediateDirectories: true
        )

        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        let resolved = created.path.withCString { path in
            realpath(path, &buffer)
        }
        url = resolved == nil
            ? created
            : URL(fileURLWithPath: String(cString: buffer), isDirectory: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    /// Writes `contents` to `name` inside the directory and returns its path.
    @discardableResult
    func write(_ contents: String, to name: String) throws -> String {
        let file = url.appendingPathComponent(name)
        try Data(contents.utf8).write(to: file)
        return file.path
    }

    func read(_ name: String) throws -> String {
        try String(
            contentsOf: url.appendingPathComponent(name),
            encoding: .utf8
        )
    }
}
