//
//  InputReader.swift
//  md
//
//  Created by Adam Wulf on 4/12/26.
//

import Foundation

enum InputReader {
    /// Read content from a file path or stdin if path is nil.
    static func read(from path: String?) throws -> String {
        if let path = path {
            let url = URL(fileURLWithPath: path)
            return try String(contentsOf: url, encoding: .utf8)
        } else {
            return readFromStdin()
        }
    }

    /// Read all of stdin into a string.
    private static func readFromStdin() -> String {
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

    /// Parse passthrough arguments into optional indices and optional file path.
    /// If the last argument doesn't parse as an Int, it's treated as a file path.
    /// If all arguments parse as Ints (or there are none), file is nil (use stdin).
    static func parsePassthrough(_ arguments: [String]) -> (indices: [Int], file: String?) {
        guard !arguments.isEmpty else {
            return (indices: [], file: nil)
        }

        // If the last arg is not an integer, treat it as a file path
        if Int(arguments.last!) == nil {
            let file = arguments.last!
            let indices = arguments.dropLast().compactMap { Int($0) }
            return (indices: indices, file: file)
        }

        // All args are integers — no file, read from stdin
        let indices = arguments.compactMap { Int($0) }
        return (indices: indices, file: nil)
    }
}
