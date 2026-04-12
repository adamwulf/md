//
//  LinesCommand.swift
//  md
//
//  Created by Adam Wulf on 4/12/26.
//

import ArgumentParser
import Foundation

struct LinesCommand: AsyncParsableCommand {

    static var configuration = CommandConfiguration(
        commandName: "lines",
        abstract: "Print lines from a file by line number"
    )

    @Flag(name: .long, help: "Print the number of lines")
    var count: Bool = false

    @Argument(
        parsing: .captureForPassthrough,
        help: "Line number or range (start end) followed by file path"
    )
    var arguments: [String]

    func run() async throws {
        guard !arguments.isEmpty else {
            throw ValidationError("Missing file path")
        }

        let file = arguments.last!
        let indices = arguments.dropLast()

        let url = URL(fileURLWithPath: file)
        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: "\n")

        if count {
            print(lines.count)
            return
        }

        guard !indices.isEmpty else {
            // No line number given, print all lines with numbers
            let width = String(lines.count).count
            for (i, line) in lines.enumerated() {
                let num = String(i + 1).leftPadded(toLength: width)
                print("\(num)  \(line)")
            }
            return
        }

        guard let start = Int(indices.first!) else {
            throw ValidationError("Invalid line number: \(indices.first!)")
        }

        let end: Int
        if indices.count > 1 {
            guard let e = Int(indices.dropFirst().first!) else {
                throw ValidationError("Invalid end line number: \(indices.dropFirst().first!)")
            }
            end = e
        } else {
            end = start
        }

        guard start >= 1, end >= start, end <= lines.count else {
            throw ValidationError("Line numbers must be in range 1...\(lines.count), got \(start)...\(end)")
        }

        for i in start...end {
            print(lines[i - 1])
        }
    }
}

private extension String {
    func leftPadded(toLength length: Int) -> String {
        if count >= length { return self }
        return String(repeating: " ", count: length - count) + self
    }
}
