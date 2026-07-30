//
//  InputReader.swift
//  md
//
//  Created by Adam Wulf on 4/12/26.
//

import Foundation

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
    static func write(_ content: String, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        let fileExists = FileManager.default.fileExists(atPath: path)
        let existingData = fileExists
            ? try Data(contentsOf: url, options: .mappedIfSafe)
            : nil
        let data = encodedUTF8(
            content,
            includeByteOrderMark: existingData?.starts(
                with: [0xEF, 0xBB, 0xBF]
            ) == true
        )

        if let existingData {
            try stage(data)

            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            do {
                try handle.seek(toOffset: 0)
                try handle.write(contentsOf: data)
                try handle.truncate(atOffset: UInt64(data.count))
                try handle.synchronize()
            } catch {
                try? handle.seek(toOffset: 0)
                try? handle.write(contentsOf: existingData)
                try? handle.truncate(atOffset: UInt64(existingData.count))
                try? handle.synchronize()
                throw error
            }
        } else {
            try data.write(to: url, options: .atomic)
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

    /// Verifies that the complete replacement can be written before touching
    /// the live file. The temporary file is unlinked while open, so a process
    /// killed by a write limit cannot leave staging debris behind.
    private static func stage(_ data: Data) throws {
        let stagingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("md-write-\(UUID().uuidString)")
        guard FileManager.default.createFile(
            atPath: stagingURL.path,
            contents: nil
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let handle = try FileHandle(forWritingTo: stagingURL)
        do {
            try FileManager.default.removeItem(at: stagingURL)
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: stagingURL)
            throw error
        }
        defer { try? handle.close() }

        try handle.write(contentsOf: data)
        try handle.synchronize()
    }
}
