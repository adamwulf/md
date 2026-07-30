//
//  InputReader.swift
//  md
//
//  Created by Adam Wulf on 4/12/26.
//

import Foundation

enum InputReader {
    /// Read content from a file path.
    static func read(from path: String) throws -> String {
        let url = URL(fileURLWithPath: path)
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Read all of stdin into a string.
    static func readFromStdin() -> String {
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

        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Write content to a file path, replacing its contents.
    static func write(_ content: String, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        let existingData = try? Data(contentsOf: url, options: .mappedIfSafe)
        if existingData?.starts(with: [0xEF, 0xBB, 0xBF]) == true {
            var data = Data([0xEF, 0xBB, 0xBF])
            data.append(contentsOf: content.utf8)
            try data.write(to: url, options: .atomic)
        } else {
            try content.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
