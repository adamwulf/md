//
//  InputReader.swift
//  md
//
//  Created by Adam Wulf on 4/12/26.
//

import Foundation
import Darwin

enum InputReader {
    struct Source {
        let content: String
        let hasUTF8ByteOrderMark: Bool
    }

    /// Read content from a file path.
    static func read(from path: String) throws -> String {
        let url = URL(fileURLWithPath: path)
        return try String(contentsOf: url, encoding: .utf8)
    }

    static func readSource(from path: String) throws -> Source {
        let content = try read(from: path)
        let data = try Data(
            contentsOf: URL(fileURLWithPath: path),
            options: .mappedIfSafe
        )
        return Source(
            content: content,
            hasUTF8ByteOrderMark: data.starts(with: [0xEF, 0xBB, 0xBF])
        )
    }

    /// Read all of stdin into a string.
    static func readFromStdin() -> String {
        readSourceFromStdin().content
    }

    static func readSourceFromStdin() -> Source {
        var data = Data()
        let bufferSize = 64 * 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while true {
            let bytesRead = fread(buffer, 1, bufferSize, stdin)
            if bytesRead > 0 {
                data.append(buffer, count: bytesRead)
            }
            if bytesRead < bufferSize { break }
        }

        return Source(
            content: String(data: data, encoding: .utf8) ?? "",
            hasUTF8ByteOrderMark: data.starts(with: [0xEF, 0xBB, 0xBF])
        )
    }

    /// Write content to a file path, replacing its contents.
    static func write(
        _ content: String,
        to path: String,
        beforeCommit: ((URL) throws -> Void)? = nil
    ) throws {
        let requestedURL = URL(fileURLWithPath: path)
        let fileExists = FileManager.default.fileExists(atPath: path)
        let existingData = fileExists
            ? try Data(contentsOf: requestedURL, options: .mappedIfSafe)
            : nil
        let data = encodedUTF8(
            content,
            includeByteOrderMark: existingData?.starts(
                with: [0xEF, 0xBB, 0xBF]
            ) == true
        )

        if existingData != nil {
            let destinationURL = requestedURL.resolvingSymlinksInPath()
            try replaceExistingFile(
                at: destinationURL,
                with: data,
                beforeCommit: beforeCommit
            )
        } else {
            try data.write(to: requestedURL, options: .atomic)
        }
    }

    static func writeToStdout(
        _ content: String,
        includeByteOrderMark: Bool
    ) throws {
        try FileHandle.standardOutput.write(
            contentsOf: encodedUTF8(
                content,
                includeByteOrderMark: includeByteOrderMark
            )
        )
    }

    static func encodedUTF8(
        _ content: String,
        includeByteOrderMark: Bool
    ) -> Data {
        var data = Data()
        if includeByteOrderMark {
            data.append(contentsOf: [0xEF, 0xBB, 0xBF])
        }
        data.append(contentsOf: content.utf8)
        return data
    }

    /// Builds a complete replacement beside the destination, then atomically
    /// renames it into place. Until the rename succeeds, the live file is never
    /// opened for writing, so staging and commit failures leave it untouched.
    private static func replaceExistingFile(
        at destinationURL: URL,
        with data: Data,
        beforeCommit: ((URL) throws -> Void)?
    ) throws {
        // A write beyond RLIMIT_FSIZE normally terminates the process before
        // Swift can unwind. Ignore SIGXFSZ while staging so the write reports
        // EFBIG instead and the cleanup defer below can remove the copy.
        let previousFileSizeSignalHandler = signal(SIGXFSZ, SIG_IGN)
        defer {
            signal(SIGXFSZ, previousFileSizeSignalHandler)
        }

        let stagingURL = destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(".md-write-\(UUID().uuidString)")
        var committed = false
        defer {
            if !committed {
                try? FileManager.default.removeItem(at: stagingURL)
            }
        }
        try FileManager.default.copyItem(at: destinationURL, to: stagingURL)

        let handle = try FileHandle(forWritingTo: stagingURL)
        defer { try? handle.close() }
        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: data)
        try handle.truncate(atOffset: UInt64(data.count))
        try handle.synchronize()
        try handle.close()

        try beforeCommit?(stagingURL)
        let result = stagingURL.path.withCString { sourcePath in
            destinationURL.path.withCString { destinationPath in
                Darwin.rename(sourcePath, destinationPath)
            }
        }
        guard result == 0 else {
            throw POSIXError(
                POSIXErrorCode(rawValue: errno) ?? .EIO
            )
        }
        committed = true
    }
}
