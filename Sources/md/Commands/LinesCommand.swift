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

    @Argument(help: "Line number or range (start end) followed by optional file path (reads stdin if omitted)")
    var input: [String] = []

    func run() async throws {
        let parsed = InputReader.parsePassthrough(input)
        let content = try InputReader.read(from: parsed.file)
        let lines = content.components(separatedBy: "\n")

        if count {
            print(lines.count)
            return
        }

        let indices = parsed.indices

        guard !indices.isEmpty else {
            // No line number given, print all lines with numbers
            let width = String(lines.count).count
            for (i, line) in lines.enumerated() {
                let num = String(i + 1).leftPadded(toLength: width)
                print("\(num)  \(line)")
            }
            return
        }

        let start = indices[0]
        let end = indices.count > 1 ? indices[1] : start

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
