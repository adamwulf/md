//
//  InputReader.swift
//  md
//
//  Created by Adam Wulf on 4/12/26.
//

import Foundation
import Darwin

enum InputReader {
    private static let fileSizeSignalLock = NSRecursiveLock()

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
        try withIgnoredFileSizeLimitSignal {
            let stagingURL = destinationURL
                .deletingLastPathComponent()
                .appendingPathComponent(".md-write-\(UUID().uuidString)")
            var committed = false
            var stagingHandle: FileHandle?
            defer {
                if !committed {
                    if let stagingHandle {
                        try? stagingHandle.seek(toOffset: 0)
                        try? stagingHandle.truncate(atOffset: 0)
                        try? stagingHandle.synchronize()
                    }
                    removeStagingFile(at: stagingURL)
                }
                try? stagingHandle?.close()
            }
            try FileManager.default.copyItem(
                at: destinationURL,
                to: stagingURL
            )
            try clearWriteBlockingFlags(at: stagingURL)

            let handle = try FileHandle(forWritingTo: stagingURL)
            stagingHandle = handle
            try handle.seek(toOffset: 0)
            try handle.write(contentsOf: data)
            try handle.truncate(atOffset: UInt64(data.count))
            try handle.synchronize()

            try beforeCommit?(stagingURL)
            let result = stagingURL.path.withCString { sourcePath in
                destinationURL.path.withCString { destinationPath in
                    Darwin.rename(sourcePath, destinationPath)
                }
            }
            guard result == 0 else {
                throw currentPOSIXError()
            }
            committed = true
        }
    }

    /// A write beyond RLIMIT_FSIZE normally terminates the process before
    /// Swift can unwind. Temporarily ignore SIGXFSZ so the write reports EFBIG
    /// and staging cleanup can run, then restore the complete prior disposition.
    private static func withIgnoredFileSizeLimitSignal<T>(
        _ body: () throws -> T
    ) throws -> T {
        fileSizeSignalLock.lock()
        defer { fileSizeSignalLock.unlock() }

        var previousDisposition = Darwin.sigaction()
        guard sigaction(
            SIGXFSZ,
            nil,
            &previousDisposition
        ) == 0 else {
            throw currentPOSIXError()
        }

        var ignoredDisposition = Darwin.sigaction()
        ignoredDisposition.__sigaction_u.__sa_handler = SIG_IGN
        guard sigemptyset(&ignoredDisposition.sa_mask) == 0 else {
            throw currentPOSIXError()
        }
        guard sigaction(
            SIGXFSZ,
            &ignoredDisposition,
            nil
        ) == 0 else {
            throw currentPOSIXError()
        }

        let result = Result { try body() }
        guard sigaction(
            SIGXFSZ,
            &previousDisposition,
            nil
        ) == 0 else {
            throw currentPOSIXError()
        }
        return try result.get()
    }

    /// The parent directory may become non-writable after staging. First scrub
    /// through the already-open file descriptor, then temporarily restore only
    /// the owner's directory access needed to unlink our private file.
    private static func removeStagingFile(at url: URL) {
        try? clearWriteBlockingFlags(at: url)
        do {
            try FileManager.default.removeItem(at: url)
            return
        } catch {
            let directoryURL = url.deletingLastPathComponent()
            var attributes = stat()
            let status = directoryURL.path.withCString { path in
                Darwin.lstat(path, &attributes)
            }
            guard status == 0 else {
                return
            }

            let originalMode = attributes.st_mode & mode_t(0o7777)
            let cleanupMode = originalMode | mode_t(S_IWUSR | S_IXUSR)
            guard cleanupMode != originalMode else {
                return
            }
            let changedMode = directoryURL.path.withCString { path in
                Darwin.chmod(path, cleanupMode)
            }
            guard changedMode == 0 else {
                return
            }
            defer {
                _ = directoryURL.path.withCString { path in
                    Darwin.chmod(path, originalMode)
                }
            }

            try? clearWriteBlockingFlags(at: url)
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Metadata copying can make the private staging file immutable or
    /// append-only. Those flags belong to the live file, not the working copy:
    /// leaving them set prevents both writing and failure cleanup.
    private static func clearWriteBlockingFlags(at url: URL) throws {
        var attributes = stat()
        let status = url.path.withCString { path in
            Darwin.lstat(path, &attributes)
        }
        guard status == 0 else {
            if errno == ENOENT {
                return
            }
            throw currentPOSIXError()
        }

        let writeBlockingFlags = UInt32(
            UF_IMMUTABLE | UF_APPEND | SF_IMMUTABLE | SF_APPEND
        )
        let writableFlags = attributes.st_flags & ~writeBlockingFlags
        guard writableFlags != attributes.st_flags else {
            return
        }

        let result = url.path.withCString { path in
            Darwin.chflags(path, writableFlags)
        }
        guard result == 0 else {
            throw currentPOSIXError()
        }
    }

    private static func currentPOSIXError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
